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

# (Bucket ARNs, Glue job name, Step Functions ARN... will be added later.)
