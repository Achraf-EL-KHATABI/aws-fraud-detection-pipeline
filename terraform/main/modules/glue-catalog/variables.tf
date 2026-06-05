###############################################################################
# Input variables for the `glue-catalog` module
#
# This module creates the AWS Glue Data Catalog database, the Glue Crawler
# that auto-discovers Parquet schemas in the curated zone, and the IAM role
# the crawler assumes.
###############################################################################

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. 'fraud-detection-dev'."
  type        = string
}

variable "account_id" {
  description = "AWS account ID, used to scope IAM permissions."
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in IAM ARNs)."
  type        = string
}

# -----------------------------------------------------------------------------
# What the crawler will scan
# -----------------------------------------------------------------------------
variable "curated_bucket_name" {
  description = "Name of the curated bucket — the Crawler reads its content."
  type        = string
}

variable "curated_bucket_arn" {
  description = "ARN of the curated bucket — used in the IAM policy."
  type        = string
}

variable "source_prefix" {
  description = "Prefix inside the curated bucket where the Parquet partitions live."
  type        = string
  default     = "transactions"
}

# -----------------------------------------------------------------------------
# Catalog configuration
# -----------------------------------------------------------------------------
variable "database_name" {
  description = "Glue Catalog database name. Must use underscores, not dashes (Athena restriction)."
  type        = string
  default     = "fraud_detection"
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
