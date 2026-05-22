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