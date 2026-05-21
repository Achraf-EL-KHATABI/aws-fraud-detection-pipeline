###############################################################################
# Provider configuration
#
# `required_providers` pins the AWS provider major version so Terraform won't
# silently jump from v5.x to v6.x and break compatibility. Locking the exact
# version is handled automatically by Terraform via the .terraform.lock.hcl
# file, which we commit on purpose (it's the equivalent of package-lock.json).
#
# `default_tags` is one of Terraform's best features: every resource managed
# by this provider gets these tags automatically. No more "I forgot to tag
# that bucket" mistakes. Tags are CRITICAL in AWS for:
#   - Cost allocation: "how much did this project cost last month?"
#   - Ownership: "who created this resource?"
#   - Automation: "kill everything tagged Environment=ephemeral after 7 days"
#   - Compliance: "list all resources missing the Owner tag"
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "aws-fraud-detection-pipeline"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Owner       = "achraf.elkhatabi"
      Repository  = "github.com/Achraf-EL-KHATABI/aws-fraud-detection-pipeline"
    }
  }
}
