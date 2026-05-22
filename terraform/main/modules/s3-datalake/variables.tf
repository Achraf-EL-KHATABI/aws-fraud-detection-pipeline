###############################################################################
# Input variables for the s3-datalake module
#
# A module exposes a clean contract: callers set these variables, the module
# does the rest. Nothing inside the module hardcodes account-specific values.
###############################################################################

variable "name_prefix" {
  description = "Prefix for all bucket names, e.g. 'fraud-detection-dev'. Buckets become <prefix>-raw, <prefix>-curated, <prefix>-analytics-<account_id>."
  type        = string
}

variable "account_id" {
  description = "AWS account ID, appended to bucket names to guarantee global uniqueness (S3 bucket names are unique worldwide)."
  type        = string
}

variable "force_destroy" {
  description = <<-EOT
    If true, `terraform destroy` will delete buckets EVEN IF they still
    contain objects. Convenient for a dev/MVP environment you tear down often.
    MUST be false in prod to avoid catastrophic data loss.
  EOT
  type        = bool
  default     = false
}

# The heart of the module: a map describing each zone of the data lake.
# Using a map + for_each lets us create N buckets from a single resource
# block, and makes adding/removing a zone a one-line change.
variable "zones" {
  description = <<-EOT
    Map of data lake zones to create. Each key is the zone name (used in the
    bucket name) and the value configures its lifecycle transitions.

    transition_ia_days     : days before objects move to STANDARD_IA (cheaper, infrequent access)
    transition_glacier_days: days before objects move to GLACIER (archive; 0 = never)
    expiration_days        : days before objects are deleted (0 = never expire)
  EOT
  type = map(object({
    transition_ia_days      = number
    transition_glacier_days = number
    expiration_days         = number
  }))

  default = {
    raw = {
      # Raw data is the immutable source of truth. Keep it, but cheaply:
      # move to IA after 30d, archive to Glacier after 90d, never delete.
      transition_ia_days      = 30
      transition_glacier_days = 90
      expiration_days         = 0
    }
    curated = {
      # Cleaned data, queried more often. Move to IA later, no Glacier.
      transition_ia_days      = 60
      transition_glacier_days = 0
      expiration_days         = 0
    }
    analytics = {
      # Hot data for dashboards/Athena. Keep in Standard, no transitions.
      transition_ia_days      = 0
      transition_glacier_days = 0
      expiration_days         = 0
    }
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which OLD (non-current) versions of an object are deleted. Controls versioning storage cost."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags merged onto every resource created by this module."
  type        = map(string)
  default     = {}
}
