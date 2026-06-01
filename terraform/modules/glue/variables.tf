###############################################################################
# Input variables for the `glue` module
#
# The module is given everything it needs to wire the Glue ETL job into the
# rest of the stack: bucket names for input/output/script, a name prefix,
# Glue runtime knobs, and any extra tags.
###############################################################################

variable "name_prefix" {
  description = "Prefix for all glue-related resource names, e.g. 'fraud-detection-dev'."
  type        = string
}

variable "account_id" {
  description = "AWS account ID, used to scope IAM permissions."
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in ARNs and S3 paths)."
  type        = string
}

# -----------------------------------------------------------------------------
# Bucket wiring
# -----------------------------------------------------------------------------
variable "raw_bucket_name" {
  description = "Name of the raw zone bucket (Glue job reads from here)."
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw zone bucket (used in the IAM policy)."
  type        = string
}

variable "curated_bucket_name" {
  description = "Name of the curated zone bucket (Glue job writes here)."
  type        = string
}

variable "curated_bucket_arn" {
  description = "ARN of the curated zone bucket (used in the IAM policy)."
  type        = string
}

# -----------------------------------------------------------------------------
# Script location
# -----------------------------------------------------------------------------
# Glue executes Python scripts stored in S3. We'll upload our local
# `glue_jobs/fraud_etl_glue.py` to a dedicated bucket (or an existing one)
# under a known prefix, and point the job at it.
variable "script_bucket_name" {
  description = "S3 bucket where the PySpark script is uploaded for Glue to execute."
  type        = string
}

variable "script_bucket_arn" {
  description = "ARN of the script bucket (used in the IAM policy)."
  type        = string
}

variable "script_local_path" {
  description = "Local filesystem path to the PySpark script that will be uploaded to S3."
  type        = string
}

variable "script_s3_key" {
  description = "S3 key (path inside the script bucket) where the script will be uploaded."
  type        = string
  default     = "glue_jobs/fraud_etl_glue.py"
}

# -----------------------------------------------------------------------------
# Glue job runtime configuration (sub-step 7.2b will use these)
# -----------------------------------------------------------------------------
variable "glue_version" {
  description = "Glue runtime version (e.g. '4.0' for Spark 3.3 / Python 3.10)."
  type        = string
  default     = "4.0"
}

variable "worker_type" {
  description = "Glue worker type. G.1X is fine for small jobs and is the cheapest."
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Number of Glue workers. 2 is the minimum and enough for our dataset."
  type        = number
  default     = 2
}

variable "job_timeout_minutes" {
  description = "Hard cap on job runtime. Prevents runaway billing if something hangs."
  type        = number
  default     = 30
}

variable "source_prefix" {
  description = "Prefix under the raw/curated buckets where the transactions live (e.g. 'transactions')."
  type        = string
  default     = "transactions"
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
