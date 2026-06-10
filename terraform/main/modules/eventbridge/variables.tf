###############################################################################
# Input variables for the `eventbridge` module
#
# Creates an EventBridge Scheduler / Rule that triggers the Step Functions
# state machine on a daily cron, plus the IAM role EventBridge assumes to
# do so.
###############################################################################

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. 'fraud-detection-dev'."
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the target Step Functions state machine."
  type        = string
}

variable "schedule_expression" {
  description = <<-EOT
    EventBridge cron expression. Default = daily at 02:00 UTC (03:00 Paris winter / 04:00 summer).
    Format: cron(minute hour day-of-month month day-of-week year)
    EventBridge uses a 6-field cron (with `year` and `?` placeholders).
  EOT
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "enabled" {
  description = "Whether the schedule is active. Disable temporarily without destroying it."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
