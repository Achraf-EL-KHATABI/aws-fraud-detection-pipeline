###############################################################################
# Outputs
#
# These values are printed at the end of `terraform apply`. We will copy
# them into ../backend.tf to configure the remote backend for the main
# Terraform project.
###############################################################################

output "tfstate_bucket_name" {
  description = "Name of the S3 bucket storing the Terraform state file."
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_bucket_arn" {
  description = "ARN of the S3 bucket storing the Terraform state file."
  value       = aws_s3_bucket.tfstate.arn
}

output "tfstate_lock_table_name" {
  description = "Name of the DynamoDB table used for state locking."
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "aws_region" {
  description = "AWS region where the backend resources live."
  value       = var.aws_region
}

output "backend_config_snippet" {
  description = "Ready-to-paste backend configuration for the main Terraform project."
  value       = <<-EOT

    Copy the block below into terraform/backend.tf:

    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.id}"
        key            = "fraud-pipeline/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
        encrypt        = true
      }
    }
  EOT
}
