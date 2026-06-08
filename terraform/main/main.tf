###############################################################################
# Main entry point for the fraud detection pipeline infrastructure
#
# This file orchestrates the modules that together form the pipeline:
#   - s3-datalake   → raw / curated / analytics buckets    (sub-step 5.3)
#   - glue          → ETL job + crawler + catalog          (later step)
#   - stepfunctions → orchestration state machine          (later step)
#   - eventbridge   → daily cron trigger                   (later step)
#   - monitoring    → CloudWatch alarms + SNS topic        (later step)
#
# For now it's intentionally empty. We're starting with the skeleton
# (providers, backend, variables) and will compose modules one by one.
###############################################################################

# Discover the AWS account ID at runtime (used to build globally-unique
# bucket names without hardcoding the account number anywhere).
data "aws_caller_identity" "current" {}

# Local values: computed once, reused everywhere. Keeps things DRY.
locals {
  account_id = data.aws_caller_identity.current.account_id

  # Name prefix applied to every resource of this stack.
  # Example: "fraud-detection-dev"
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags merged on top of the provider's default_tags when a
  # module needs extra context (e.g. a Component tag).
  common_tags = {
    Stack = local.name_prefix
  }
}


###############################################################################
# Data lake (S3) — raw / curated / analytics zones
###############################################################################
module "s3_datalake" {
  source = "./modules/s3-datalake"

  name_prefix = local.name_prefix
  account_id  = local.account_id

  # In dev we allow tearing the lake down even if it still holds objects.
  # Set to false (or remove) for any non-dev environment.
  force_destroy = true

  # Extra tags merged on top of the provider's default_tags.
  tags = local.common_tags
}

###############################################################################
# Glue ETL job — scores transactions in raw and writes results to curated
###############################################################################
module "glue" {
  source = "./modules/glue"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  aws_region  = var.aws_region

  # Wire the data lake buckets created by the s3-datalake module.
  raw_bucket_name     = module.s3_datalake.raw_bucket_name
  raw_bucket_arn      = module.s3_datalake.raw_bucket_arn
  curated_bucket_name = module.s3_datalake.curated_bucket_name
  curated_bucket_arn  = module.s3_datalake.curated_bucket_arn

  # We reuse the raw bucket for storing the script (one bucket fewer to manage).
  # In a strict prod setup you'd use a dedicated artifacts bucket.
  script_bucket_name = module.s3_datalake.raw_bucket_name
  script_bucket_arn  = module.s3_datalake.raw_bucket_arn
  script_local_path  = "${path.root}/../../glue_jobs/fraud_etl_glue.py"

  tags = local.common_tags
}

###############################################################################
# Glue Data Catalog + Crawler — makes the curated zone queryable by Athena
###############################################################################
module "glue_catalog" {
  source = "./modules/glue-catalog"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  aws_region  = var.aws_region

  curated_bucket_name = module.s3_datalake.curated_bucket_name
  curated_bucket_arn  = module.s3_datalake.curated_bucket_arn

  tags = local.common_tags
}

###############################################################################
# Athena — interactive SQL on top of the curated Parquet zone
###############################################################################
module "athena" {
  source = "./modules/athena"

  name_prefix = local.name_prefix
  account_id  = local.account_id

  tags = local.common_tags
}

###############################################################################
# Step Functions — daily batch orchestration (run Glue Job, then Crawler)
###############################################################################
module "stepfunctions" {
  source = "./modules/stepfunctions"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  aws_region  = var.aws_region

  glue_job_name     = module.glue.glue_job_name
  glue_crawler_name = module.glue_catalog.crawler_name

  tags = local.common_tags
}
