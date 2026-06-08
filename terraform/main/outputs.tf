###############################################################################
# Project-level outputs
#
# These are values that get printed at the end of `terraform apply`
# and stored in the state file. Useful for:
#   - Quick visual inspection ("what's the bucket name again?")
#   - Cross-project references ("the Glue job needs the raw bucket ARN")
#   - CI/CD steps that consume Terraform outputs as inputs
#
# Currently empty — module outputs will be exposed here once modules
# are wired into main.tf (sub-step 5.3).
###############################################################################

output "account_id" {
  description = "AWS account ID where the infrastructure is deployed."
  value       = local.account_id
}

output "aws_region" {
  description = "AWS region where the infrastructure is deployed."
  value       = var.aws_region
}

output "name_prefix" {
  description = "Common prefix applied to all resources of this stack."
  value       = local.name_prefix
}

###############################################################################
# Data lake outputs (surfaced from the s3-datalake module)
###############################################################################
output "datalake_bucket_names" {
  description = "Map of data lake zone => bucket name."
  value       = module.s3_datalake.bucket_names
}

output "datalake_bucket_arns" {
  description = "Map of data lake zone => bucket ARN."
  value       = module.s3_datalake.bucket_arns
}

###############################################################################
# Glue outputs (surfaced from the glue module)
###############################################################################
output "glue_job_name" {
  description = "Name of the Glue ETL job (use it to start the job via CLI/console)."
  value       = module.glue.glue_job_name
}

output "glue_role_arn" {
  description = "ARN of the IAM role assumed by the Glue ETL job."
  value       = module.glue.glue_role_arn
}

output "glue_script_uri" {
  description = "S3 URI where the PySpark script is hosted for Glue."
  value       = module.glue.script_s3_uri
}

###############################################################################
# Glue Catalog outputs (surfaced from the glue-catalog module)
###############################################################################
output "glue_database_name" {
  description = "Glue Catalog database name (used in Athena queries: SELECT ... FROM <db>.transactions)."
  value       = module.glue_catalog.database_name
}

output "glue_crawler_name" {
  description = "Name of the Crawler. Start it with: aws glue start-crawler --name <this>."
  value       = module.glue_catalog.crawler_name
}


###############################################################################
# Athena outputs (surfaced from the athena module)
###############################################################################
output "athena_workgroup_name" {
  description = "Athena workgroup to select before running queries."
  value       = module.athena.workgroup_name
}

output "athena_results_location" {
  description = "S3 URI where Athena writes query results."
  value       = module.athena.results_location
}

###############################################################################
# Step Functions outputs (surfaced from the stepfunctions module)
###############################################################################
output "stepfunctions_state_machine_arn" {
  description = "ARN of the orchestrator state machine."
  value       = module.stepfunctions.state_machine_arn
}

output "stepfunctions_state_machine_name" {
  description = "Name of the orchestrator state machine."
  value       = module.stepfunctions.state_machine_name
}
