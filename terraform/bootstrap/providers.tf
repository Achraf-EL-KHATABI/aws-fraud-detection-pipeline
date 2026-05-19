terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Note: NO backend block here.
  # This bootstrap project uses LOCAL state intentionally — it's the chicken-and-egg
  # problem: we need to create the S3 backend before we can use it.
  # The local state file (terraform.tfstate) is gitignored.
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "aws-fraud-detection-pipeline"
      ManagedBy   = "Terraform"
      Component   = "bootstrap"
      Environment = "shared"
      Owner       = "achraf.elkhatabi"
    }
  }
}
