###############################################################################
# GitHub Actions OIDC trust setup
#
# This file wires GitHub Actions into AWS without using static credentials.
#
# 1. We register GitHub's public OIDC issuer as a trusted identity provider
#    inside our AWS account.
# 2. We create an IAM role whose trust policy ONLY accepts tokens that
#    were issued for our specific repository + specific git refs.
# 3. We attach a policy granting that role the AWS permissions it needs
#    to deploy the pipeline infrastructure.
#
# Once applied, the GitHub Actions workflow can call sts:AssumeRoleWithWebIdentity
# and receive short-lived credentials. Nothing is ever stored.
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Github's public OIDC issuer URL (constant, documented by GitHub).
  github_oidc_url = "https://token.actions.githubusercontent.com"

  # Audience: must match the `aud` claim that GitHub injects in its JWT.
  # `sts.amazonaws.com` is the AWS-recommended value used by the
  # official `aws-actions/configure-aws-credentials` action.
  github_oidc_audience = "sts.amazonaws.com"

  # Build the list of fully-qualified `sub` claims that we trust.
  # Format: repo:OWNER/REPO:GIT_REF
  trusted_subs = [
    for ref in var.allowed_branches :
    "repo:${var.github_org}/${var.github_repo}:${ref}"
  ]
}

# -----------------------------------------------------------------------------
# 1. Register GitHub as an OIDC identity provider in this AWS account
# -----------------------------------------------------------------------------
# Thumbprints are AWS's way of pinning the TLS certificate of the OIDC
# issuer. We let the provider compute them automatically via the
# `tls_certificate` data source so we never have to maintain them by hand.
data "tls_certificate" "github_oidc" {
  url = local.github_oidc_url
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = local.github_oidc_url
  client_id_list  = [local.github_oidc_audience]
  thumbprint_list = [data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name = "github-actions-oidc"
  }
}

# -----------------------------------------------------------------------------
# 2. Trust policy: only OUR repo + OUR allowed branches can assume the role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "AllowGithubActionsToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # The audience must match what GitHub puts in the JWT.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = [local.github_oidc_audience]
    }

    # The `sub` claim restricts WHICH workflow can assume the role.
    # We pin it to our exact repository and exact branch(es).
    # Without this, ANY GitHub repo could assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.trusted_subs
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  description        = "Role assumed by GitHub Actions via OIDC to deploy the fraud detection pipeline."
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  # Max session = 1 hour. Forces re-authentication for long-running jobs.
  max_session_duration = 3600

  tags = {
    Name = var.role_name
  }
}

# -----------------------------------------------------------------------------
# 3. Permissions granted to the role
# -----------------------------------------------------------------------------
# For a weekend MVP, we attach a broad managed policy that covers everything
# Terraform will need (S3, Glue, Athena, Step Functions, EventBridge, IAM, etc.)
#
# In a real production setup, you would build a custom least-privilege policy
# listing only the exact API calls used by the pipeline. We'll do that in
# a "V2 hardening" iteration so the project stays moving for now.
#
# Note: PowerUserAccess does NOT grant IAM management. Since Terraform will
# need to create IAM roles for Glue, Step Functions, etc., we add a narrow
# IAM policy on top.
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Inline IAM policy that grants exactly what Terraform needs to manage the
# service roles of the pipeline (Glue, Step Functions, EventBridge) WITHOUT
# granting broad iam:* (which would let the role escalate to admin).
data "aws_iam_policy_document" "iam_for_pipeline" {
  statement {
    sid    = "ManagePipelineServiceRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
    ]
    # Only roles whose name starts with our project prefix can be managed.
    # This prevents the CI from touching unrelated roles in the account.
    resources = ["arn:aws:iam::${local.account_id}:role/fraud-detection-*"]
  }

  statement {
    sid    = "ReadOnlyIamForPlan"
    effect = "Allow"
    actions = [
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "iam_for_pipeline" {
  name        = "${var.role_name}-iam-management"
  description = "Allows the GitHub Actions role to manage the pipeline's service roles only."
  policy      = data.aws_iam_policy_document.iam_for_pipeline.json
}

resource "aws_iam_role_policy_attachment" "iam_for_pipeline" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.iam_for_pipeline.arn
}
