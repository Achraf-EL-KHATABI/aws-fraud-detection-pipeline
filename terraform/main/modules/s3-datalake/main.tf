###############################################################################
# s3-datalake module — core resources
#
# Creates one S3 bucket per data lake zone (raw / curated / analytics) plus
# all the security and lifecycle configuration each bucket needs.
#
# Design choices:
#   - `for_each = var.zones` generates N buckets from ONE resource block.
#     The map key (e.g. "raw") becomes each.key; the value object is each.value.
#   - Bucket names: "<prefix>-<zone>-<account_id>" for global uniqueness.
#   - SSE-S3 (AES256) encryption — free, AWS-managed keys, fine for an MVP.
#   - Versioning ON everywhere — protects against accidental overwrite/delete.
#   - Public access fully blocked — defense in depth.
###############################################################################

locals {
  # Build the final bucket name for each zone, e.g.:
  #   fraud-detection-dev-raw-424414904672
  bucket_names = {
    for zone, cfg in var.zones :
    zone => "${var.name_prefix}-${zone}-${var.account_id}"
  }

  # A zone needs the "current version transitions" rule ONLY if at least one
  # action (IA transition, Glacier transition, or expiration) is configured.
  # Without this guard, a zone with all-zero settings (e.g. "analytics") would
  # produce an empty lifecycle rule, which AWS rejects with:
  #   "At least one action needs to be specified in a rule".
  zones_with_current_actions = {
    for zone, cfg in var.zones : zone => cfg
    if cfg.transition_ia_days > 0 || cfg.transition_glacier_days > 0 || cfg.expiration_days > 0
  }
}

# -----------------------------------------------------------------------------
# The buckets themselves (one per zone, via for_each)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  for_each = var.zones

  bucket        = local.bucket_names[each.key]
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name      = local.bucket_names[each.key]
    Zone      = each.key
    Component = "s3-datalake"
  })
}

# -----------------------------------------------------------------------------
# Block ALL public access on every bucket (4 independent switches)
# -----------------------------------------------------------------------------
# This is the single most important S3 security control. Even if a bad ACL
# or bucket policy is added later, public exposure stays impossible.
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Versioning — keep historical versions of every object
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# Server-side encryption at rest (SSE-S3 / AES256)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# Lifecycle rules — cost optimization per zone
# -----------------------------------------------------------------------------
# Every bucket gets at least the non-current cleanup and incomplete-multipart
# hygiene rules. The "current version transitions" rule is added ONLY for
# zones that actually configure a transition/expiration (see the local
# `zones_with_current_actions`). This avoids empty-rule errors from AWS.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = var.zones

  bucket = aws_s3_bucket.this[each.key].id

  # ---- Rule 1 (conditional): transition + expire CURRENT object versions ----
  # Rendered only when this zone has at least one current-version action.
  dynamic "rule" {
    for_each = contains(keys(local.zones_with_current_actions), each.key) ? [1] : []
    content {
      id     = "${each.key}-current-version-transitions"
      status = "Enabled"

      filter {} # apply to all objects in the bucket

      # Move to STANDARD_IA after N days (only if configured > 0)
      dynamic "transition" {
        for_each = each.value.transition_ia_days > 0 ? [1] : []
        content {
          days          = each.value.transition_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      # Move to GLACIER after N days (only if configured > 0)
      dynamic "transition" {
        for_each = each.value.transition_glacier_days > 0 ? [1] : []
        content {
          days          = each.value.transition_glacier_days
          storage_class = "GLACIER"
        }
      }

      # Expire (delete) current versions after N days (only if configured > 0)
      dynamic "expiration" {
        for_each = each.value.expiration_days > 0 ? [1] : []
        content {
          days = each.value.expiration_days
        }
      }
    }
  }

  # ---- Rule 2: clean up OLD (non-current) versions ----------------------
  # Versioning keeps every overwrite forever by default. This rule deletes
  # superseded versions after N days to control storage cost.
  rule {
    id     = "${each.key}-noncurrent-version-cleanup"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # ---- Rule 3: abort incomplete multipart uploads -----------------------
  # Failed/abandoned multipart uploads silently accrue storage charges.
  # This is a no-brainer hygiene rule every production bucket should have.
  rule {
    id     = "${each.key}-abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
