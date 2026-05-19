# IAM OIDC — GitHub Actions trust setup

This sub-project creates the AWS-side trust configuration that lets the
project's **GitHub Actions** workflows authenticate to AWS **without static
credentials** (no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` ever stored
in repository secrets).

It provisions:

1. An **OIDC identity provider** that trusts `https://token.actions.githubusercontent.com`.
2. An **IAM role** (`fraud-detection-github-actions`) whose trust policy
   only accepts tokens issued for `Achraf-EL-KHATABI/aws-fraud-detection-pipeline`
   on the `main` branch.
3. The permissions the role needs to deploy the pipeline.

## Apply

```bash
cd terraform/iam-oidc
terraform init
terraform plan
terraform apply
```

At the end, copy the value of `github_actions_role_arn` into your GitHub
repository:

> Settings → Secrets and variables → Actions → New repository secret
>
> Name: `AWS_DEPLOY_ROLE_ARN`
> Value: `arn:aws:iam::<account-id>:role/fraud-detection-github-actions`

## State

This sub-project's state lives in the shared backend (S3 bucket created by
`../bootstrap`) under the key `iam-oidc/terraform.tfstate`, separate from
the main pipeline state.
