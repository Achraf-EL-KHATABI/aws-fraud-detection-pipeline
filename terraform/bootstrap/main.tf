###############################################################################
# Bootstrap resources for the remote Terraform backend
#
# This file creates exactly two resources:
#   1. An S3 bucket to store the Terraform state file (versioned + encrypted).
#   2. A DynamoDB table used as the state-locking mechanism.
#
# Apply this project ONCE manually with local state, then commit the local
# state file? -> NO. The local tfstate is gitignored. Losing it is harmless:
# you can always `terraform import` these two resources again, or recreate
# them. They contain no application data.
###############################################################################

# Discover the current AWS account ID so we can suffix the bucket name
# and guarantee global uniqueness without manual edits.
data "aws_caller_identity" "current" {}

locals {
  account_id          = data.aws_caller_identity.current.account_id
  tfstate_bucket_name = "${var.project_name}-tfstate-${local.account_id}"
  tfstate_lock_table  = "${var.project_name}-tfstate-lock"
}

# -----------------------------------------------------------------------------
# S3 bucket holding the Terraform state file
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.tfstate_bucket_name

  # Safety net: prevent `terraform destroy` from wiping the state bucket
  # by accident. To delete this bucket later, you must first remove this
  # block, run `terraform apply`, then `terraform destroy`.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = local.tfstate_bucket_name
    Description = "Stores remote Terraform state for the fraud detection pipeline"
  }
}

# Block ALL public access at the bucket level (defense in depth — even if a
# bad bucket policy is added later, public access remains impossible).
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning so we can roll back to a previous state if something
# goes wrong (e.g., a botched `terraform apply` that corrupts the file).
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption at rest using AWS-managed keys (SSE-S3).
# We don't use a customer-managed KMS key here to keep the bootstrap cheap
# and simple. The state file is in a private bucket already.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: expire old non-current versions after 90 days to avoid
# accumulating obsolete state copies forever.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# -----------------------------------------------------------------------------
# DynamoDB table used by Terraform for state locking
# -----------------------------------------------------------------------------
# Terraform writes a lock record keyed by `LockID` whenever it starts an
# operation. If a second process tries to run at the same time it sees the
# lock and refuses to proceed, preventing state corruption.
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = local.tfstate_lock_table
  billing_mode = "PAY_PER_REQUEST" # on-demand: ~free for our usage
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = local.tfstate_lock_table
    Description = "Terraform state locking table for the fraud detection pipeline"
  }
}
