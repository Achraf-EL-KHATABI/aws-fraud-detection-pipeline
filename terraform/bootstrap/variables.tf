variable "aws_region" {
  description = "AWS region where bootstrap resources will be created."
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "Local AWS CLI profile name used to authenticate the bootstrap apply."
  type        = string
  default     = "project-profile"
}

variable "project_name" {
  description = "Short project identifier used as a prefix for bootstrap resources."
  type        = string
  default     = "fraud-detection"
}
