# Module `athena`

Provisions an Amazon Athena workgroup and the dedicated S3 bucket that
stores query results, with built-in cost and security guardrails.

## What it creates

- **`aws_s3_bucket`** — `<prefix>-athena-results-<account_id>`, with:
  - Public access fully blocked
  - SSE-S3 encryption at rest
  - Lifecycle rule: query result files expire after `results_retention_days`
- **`aws_athena_workgroup`** — `fraud-detection`, with:
  - **`enforce_workgroup_configuration = true`** — users can't override the
    output location or encryption per query
  - **`bytes_scanned_cutoff_per_query = 100 MB`** — hard cost guardrail
  - CloudWatch metrics published
  - Default output location pointing at the results bucket

## Usage

```hcl
module "athena" {
  source = "./modules/athena"

  name_prefix = local.name_prefix
  account_id  = local.account_id

  tags = local.common_tags
}
```

## Running queries

1. Console → Athena → top-right workgroup selector → **`fraud-detection`**
2. Pick the database **`fraud_detection`** in the left panel
3. Paste a query from `athena/queries/` and run

Or from the CLI:

```bash
aws athena start-query-execution \
    --work-group fraud-detection \
    --query-string "SELECT risk_level, COUNT(*) FROM fraud_detection.transactions GROUP BY risk_level;" \
    --profile project-profile --region eu-west-3
```

## Why a dedicated workgroup?

- **Isolation** — queries of this project never mix with the AWS-default
  `primary` workgroup
- **Cost control** — every query is capped at 100 MB scanned
- **Audit** — CloudWatch metrics per workgroup let us track usage
- **Compliance** — all results forced to SSE-S3 + a known bucket
