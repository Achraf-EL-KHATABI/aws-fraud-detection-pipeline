terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote backend: this sub-project uses the S3 bucket + DynamoDB table
  # created by the bootstrap project. Its state lives at a dedicated key
  # so it never collides with the main project's state.
  backend "s3" {
    bucket         = "fraud-detection-tfstate-424414904672"
    key            = "iam-oidc/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "fraud-detection-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "aws-fraud-detection-pipeline"
      ManagedBy   = "Terraform"
      Component   = "iam-oidc"
      Environment = "shared"
      Owner       = "achraf.elkhatabi"
    }
  }
}
