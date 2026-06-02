###############################################################################
# glue module — IAM role + PySpark script upload (sub-step 7.2a)
#
# This file provisions everything the Glue Job needs to EXIST and be ABLE
# to run. The job resource itself is added in sub-step 7.2b.
#
# What we create here:
#   1. aws_s3_object        — uploads the local PySpark script to S3 (Glue
#                             only knows how to run scripts from S3, not
#                             from your laptop).
#   2. aws_iam_role         — the identity Glue assumes when it runs the job.
#   3. aws_iam_policy       — a least-privilege custom policy attached to it.
#   4. AWS-managed policy   — AWSGlueServiceRole for the standard Glue
#                             plumbing (CloudWatch metrics, Glue API calls).
#
# IMPORTANT principle: the policy is SCOPED to our buckets, not "s3:*" on
# all of S3. This is the textbook AWS hardening pattern recruiters want
# to see.
###############################################################################

# -----------------------------------------------------------------------------
# 1. Upload the local PySpark script to S3 so Glue can execute it.
# -----------------------------------------------------------------------------
# `etag = filemd5(...)` means: if the local file changes, Terraform re-uploads
# the new version on the next `apply`. Without this, the file would only be
# uploaded once and stale forever.
resource "aws_s3_object" "fraud_etl_script" {
  bucket = var.script_bucket_name
  key    = var.script_s3_key
  source = var.script_local_path
  etag   = filemd5(var.script_local_path)

  content_type = "text/x-python"

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-fraud-etl-script"
    Component = "glue"
  })
}

# -----------------------------------------------------------------------------
# 2. IAM trust policy: only the Glue service can assume this role.
# -----------------------------------------------------------------------------
# A trust policy answers the question "who is allowed to USE this role?".
# Here, only the AWS Glue service principal — nobody else.
data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    sid     = "AllowGlueToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_job" {
  name               = "${var.name_prefix}-glue-fraud-etl"
  description        = "Role assumed by the Glue fraud-detection ETL job."
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-glue-fraud-etl"
    Component = "glue"
  })
}

# -----------------------------------------------------------------------------
# 3. AWS-managed policy: standard Glue plumbing
# -----------------------------------------------------------------------------
# AWSGlueServiceRole covers the Glue API calls (job lifecycle, metrics,
# CloudWatch Logs publishing for the job itself). It does NOT grant S3
# data access — we handle that with the custom policy below.
resource "aws_iam_role_policy_attachment" "glue_managed" {
  role       = aws_iam_role.glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# -----------------------------------------------------------------------------
# 4. Custom least-privilege policy: only OUR buckets, only what's needed
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "glue_data_access" {
  # Read raw data
  statement {
    sid    = "ReadRawZone"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
    ]
  }

  # Write curated data (and read it back, e.g. for overwrite)
  statement {
    sid    = "WriteCuratedZone"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.curated_bucket_arn,
      "${var.curated_bucket_arn}/*",
    ]
  }

  # Read the script Glue is supposed to execute
  statement {
    sid    = "ReadScript"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.script_bucket_arn,
      "${var.script_bucket_arn}/*",
    ]
  }

  # Allow the job to write its own logs to CloudWatch Logs
  # (Glue creates log groups under /aws-glue/jobs/* automatically.)
  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws-glue/*",
    ]
  }
}

resource "aws_iam_policy" "glue_data_access" {
  name        = "${var.name_prefix}-glue-fraud-etl-data"
  description = "Least-privilege S3 + Logs access for the fraud ETL Glue job."
  policy      = data.aws_iam_policy_document.glue_data_access.json
}

resource "aws_iam_role_policy_attachment" "glue_data_access" {
  role       = aws_iam_role.glue_job.name
  policy_arn = aws_iam_policy.glue_data_access.arn
}


# -----------------------------------------------------------------------------
# 5. The Glue Job itself
# -----------------------------------------------------------------------------
# This is the resource that "exists" in AWS as a runnable job. Once created,
# it can be started from the console, the CLI, Step Functions, or EventBridge.
#
# Key configuration:
#   - command.script_location: S3 URI of the PySpark script (from step 1).
#   - command.python_version: must be "3" for Glue 4.0.
#   - glue_version: pins the Spark/Python runtime.
#   - worker_type + number_of_workers: how big and how many Spark executors.
#   - default_arguments: parameters injected into our PySpark script.
#
# Note on the script_location dependency:
#   We pass aws_s3_object.fraud_etl_script.key (not just the literal key)
#   so Terraform infers the dependency: the script MUST be uploaded before
#   the job is created/updated. This avoids race conditions on first apply.
resource "aws_glue_job" "fraud_etl" {
  name        = "${var.name_prefix}-fraud-etl"
  description = "Scores transactions with fraud-detection rules; raw -> curated."
  role_arn    = aws_iam_role.glue_job.arn

  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.job_timeout_minutes

  command {
    name            = "glueetl" # 'glueetl' = Spark job (vs 'pythonshell')
    script_location = "s3://${var.script_bucket_name}/${aws_s3_object.fraud_etl_script.key}"
    python_version  = "3"
  }

  # Arguments injected into the PySpark script. Glue conventions:
  #   - Keys MUST start with "--".
  #   - "--JOB_NAME" is added automatically by Glue, no need to set it here.
  #   - Other AWS-recommended defaults below enable logging, metrics, etc.
  default_arguments = {
    # Our script's custom inputs
    "--raw_bucket"     = var.raw_bucket_name
    "--curated_bucket" = var.curated_bucket_name
    "--source_prefix"  = var.source_prefix

    # AWS-recommended defaults for Glue 4.0
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "false"
    "--job-language"                     = "python"
    "--TempDir"                          = "s3://${var.curated_bucket_name}/_glue_temp/"
  }

  # Retry once on transient failure (network glitch, spot interruption, etc.).
  execution_property {
    max_concurrent_runs = 1
  }

  max_retries = 1

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-fraud-etl"
    Component = "glue"
  })
}

