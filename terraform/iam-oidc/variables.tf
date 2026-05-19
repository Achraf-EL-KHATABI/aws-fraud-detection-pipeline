variable "aws_region" {
  description = "AWS region for the OIDC provider and IAM role."
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used for the initial apply of this project."
  type        = string
  default     = "project-profile"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
  default     = "Achraf-EL-KHATABI"
}

variable "github_repo" {
  description = "GitHub repository name (without the owner/ prefix)."
  type        = string
  default     = "aws-fraud-detection-pipeline"
}

variable "allowed_branches" {
  description = <<-EOT
    List of git refs that are allowed to assume the deployment role.
    Examples: "ref:refs/heads/main", "ref:refs/heads/develop".
    Pull requests use "pull_request" but we deliberately restrict
    deployments to specific branches only.
  EOT
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  type        = string
  default     = "fraud-detection-github-actions"
}
