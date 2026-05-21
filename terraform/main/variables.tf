###############################################################################
# Global variables for the main Terraform project
#
# Each variable has a `type`, a `description`, and usually a `default`.
# Variables WITHOUT a default are mandatory (Terraform asks at runtime).
#
# Validation blocks are used where it's worth catching errors EARLY, before
# any AWS API call is made. For example, ensuring the region is one we
# support saves us from "Bucket region mismatch" errors 5 minutes later.
###############################################################################

variable "aws_region" {
  description = "AWS region where the pipeline infrastructure is deployed."
  type        = string
  default     = "eu-west-3"

  validation {
    condition     = contains(["eu-west-1", "eu-west-3", "eu-central-1"], var.aws_region)
    error_message = "Region must be one of: eu-west-1 (Ireland), eu-west-3 (Paris), eu-central-1 (Frankfurt)."
  }
}

variable "aws_profile" {
  description = "Local AWS CLI profile used for terraform commands on this workstation. CI/CD ignores it (uses OIDC)."
  type        = string
  default     = "project-profile"
}

variable "project_name" {
  description = "Short identifier used as a prefix for all resource names. Lowercase, dashes only."
  type        = string
  default     = "fraud-detection"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3-31 chars, lowercase letters, digits, dashes only, and start with a letter."
  }
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod. Influences resource sizing and lifecycle rules."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
