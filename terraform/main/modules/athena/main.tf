###############################################################################
# athena module — Workgroup + dedicated results bucket
#
# Creates:
#   1. aws_s3_bucket           — stores Athena query results (CSV per query)
#                                 + public-access-block + versioning OFF
#                                 (versioning would waste storage on transient
#                                 result files)
#   2. aws_s3_bucket_lifecycle — auto-expire result files after N days
#   3. aws_athena_workgroup    — the workgroup that enforces:
#                                  - result location & SSE-S3 encryption
#                                  - per-query bytes scanned cutoff
#                                  - publishing metrics to CloudWatch
###############################################################################

locals {
  # S3 bucket names are globally unique, so we suffix with the account id.
  results_bucket_name = "${var.name_prefix}-athena-results-${var.account_id}"
}

# -----------------------------------------------------------------------------
# 1. The results bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "results" {
  bucket = local.results_bucket_name

  # Athena results are transient by nature — allow destroy with content
  # so a `terraform destroy` in dev doesn't get stuck on leftover CSVs.
  force_destroy = true

  tags = merge(var.tags, {
    Name      = local.results_bucket_name
    Component = "athena"
    Purpose   = "athena-query-results"
  })
}

# Block ALL public access (defense in depth, same pattern as the data lake).
resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption (SSE-S3, free, AWS-managed key).
resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: expire query results after N days. Athena re-runs are cheap;
# keeping ancient CSVs forever is pure storage waste.
resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-old-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = var.results_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# -----------------------------------------------------------------------------
# 2. The Athena workgroup
# -----------------------------------------------------------------------------
# A workgroup is the unit Athena uses to isolate queries, enforce settings,
# and report cost metrics. We use a project-specific workgroup so this
# project's queries never bleed into the AWS-default `primary` workgroup.
resource "aws_athena_workgroup" "this" {
  name        = var.workgroup_name
  description = "Workgroup for the fraud-detection pipeline queries."

  # `state` Enabled = workgroup accepts new queries.
  state = "ENABLED"

  configuration {
    # Force every query in this workgroup to use OUR settings (location,
    # encryption, scan limit). Users can't override on a per-query basis.
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    # Hard scan limit — protects against runaway "SELECT * FROM huge_table"
    # cost surprises.
    bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff_per_query

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.id}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  # If we ever `terraform destroy`, this lets Athena drop the workgroup
  # even if query history exists.
  force_destroy = true

  tags = merge(var.tags, {
    Name      = var.workgroup_name
    Component = "athena"
  })
}
