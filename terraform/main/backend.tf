###############################################################################
# Remote backend configuration for the MAIN Terraform project
#
# This file tells Terraform WHERE to store the state file of this project.
# It reuses the S3 bucket and DynamoDB table that were created by the
# bootstrap project (terraform/bootstrap/).
#
# IMPORTANT — about the `key` attribute:
#   This is the path INSIDE the bucket where the state lives.
#   We use a dedicated subfolder ("main/") so this project's state never
#   collides with the bootstrap's state ("bootstrap/") or the OIDC
#   project's state ("iam-oidc/"). All three live peacefully in the same
#   bucket, isolated by their key prefix.
#
# Why a separate file for the backend block?
#   Pure convention. The backend could also live in providers.tf or main.tf,
#   but having a dedicated backend.tf makes the project's "infrastructure
#   contract" instantly visible to any reviewer opening the repo.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "fraud-detection-tfstate-424414904672"
    key            = "main/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "fraud-detection-tfstate-lock"
    encrypt        = true
  }
}
