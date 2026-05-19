output "github_actions_role_arn" {
  description = <<-EOT
    ARN of the IAM role assumable by GitHub Actions.
    Copy this value into the GitHub repository secret `AWS_DEPLOY_ROLE_ARN`
    (Repo Settings -> Secrets and variables -> Actions -> New repository secret).
  EOT
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role used by GitHub Actions."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider registered in this account."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "trusted_subjects" {
  description = "The list of trusted GitHub `sub` claims this role accepts."
  value       = local.trusted_subs
}
