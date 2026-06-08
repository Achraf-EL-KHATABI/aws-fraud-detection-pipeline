###############################################################################
# Input variables for the `stepfunctions` module
#
# Builds a Step Functions state machine that orchestrates the daily batch:
#   1. Start the Glue ETL job and wait for it to finish.
#   2. Start the Glue Crawler so Athena picks up new partitions.
#
# The machine references existing resources (job name, crawler name) — it
# does not create them.
###############################################################################

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. 'fraud-detection-dev'."
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used to scope IAM permissions."
  type        = string
}

variable "aws_region" {
  description = "AWS region — used in IAM ARNs and CloudWatch log groups."
  type        = string
}

# -----------------------------------------------------------------------------
# Targets the state machine will invoke
# -----------------------------------------------------------------------------
variable "glue_job_name" {
  description = "Name of the Glue ETL job the state machine will trigger."
  type        = string
}

variable "glue_crawler_name" {
  description = "Name of the Glue Crawler the state machine will trigger after the job."
  type        = string
}

variable "log_retention_days" {
  description = "How long to keep state-machine execution logs in CloudWatch."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
