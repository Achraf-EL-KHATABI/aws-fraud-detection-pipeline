###############################################################################
# Input variables for the `athena` module
#
# Provisions an Athena workgroup and the S3 bucket Athena uses to store
# the CSV result of every query. The workgroup also enforces cost controls
# (per-query bytes limit) and result encryption.
###############################################################################

variable "name_prefix" {
  description = "Prefix for resource names, e.g. 'fraud-detection-dev'."
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used to make the results bucket name globally unique."
  type        = string
}

variable "workgroup_name" {
  description = "Athena workgroup name. A workgroup isolates queries, results and cost limits."
  type        = string
  default     = "fraud-detection"
}

variable "bytes_scanned_cutoff_per_query" {
  description = <<-EOT
    Hard cap on the bytes a single query is allowed to scan. Athena bills
    per byte scanned, so this is the cheap-and-cheerful cost guardrail.
    100 MB is plenty for our 14 small Parquet files; you can raise it later.
  EOT
  type        = number
  default     = 100 * 1024 * 1024 # 100 MB
}

variable "results_retention_days" {
  description = "Days after which Athena query result files expire (cost hygiene)."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
