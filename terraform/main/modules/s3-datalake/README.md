# Module `s3-datalake`

Creates the S3 data lake for the fraud detection pipeline, following a
3-zone **medallion architecture**:

| Zone | Role | Typical format |
|------|------|----------------|
| `raw` (bronze) | Immutable source of truth, as ingested | CSV / JSON |
| `curated` (silver) | Cleaned, typed, partitioned | Parquet |
| `analytics` (gold) | Aggregated, query-ready for BI | Parquet |

Each bucket is created with:

- **Public access fully blocked** (4 switches)
- **Versioning enabled**
- **SSE-S3 (AES256) encryption** at rest
- **Per-zone lifecycle rules** (Standard → IA → Glacier transitions)
- **Non-current version cleanup** and **incomplete-multipart abort** hygiene rules

## Usage

```hcl
module "s3_datalake" {
  source = "./modules/s3-datalake"

  name_prefix = "fraud-detection-dev"
  account_id  = data.aws_caller_identity.current.account_id

  # Optional: override defaults
  force_destroy = true  # dev only — allows destroy with objects present
  tags          = { Stack = "fraud-detection-dev" }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name_prefix` | string | — | Prefix for bucket names |
| `account_id` | string | — | AWS account ID (bucket name uniqueness) |
| `force_destroy` | bool | `false` | Allow destroy with objects present (dev only) |
| `zones` | map(object) | raw/curated/analytics | Per-zone lifecycle config |
| `noncurrent_version_expiration_days` | number | `90` | Days before old versions deleted |
| `tags` | map(string) | `{}` | Extra tags merged onto resources |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_names` | Map zone => bucket name |
| `bucket_arns` | Map zone => bucket ARN |
| `bucket_domain_names` | Map zone => regional domain name |
| `raw_bucket_name` / `raw_bucket_arn` | Convenience accessors for the raw zone |
| `curated_bucket_name` / `curated_bucket_arn` | Convenience accessors for the curated zone |
| `analytics_bucket_name` / `analytics_bucket_arn` | Convenience accessors for the analytics zone |

## Notes

- **Encryption**: SSE-S3 is used to keep the MVP free. For production,
  switch to a customer-managed KMS key for granular access control and
  audit logging.
- **`force_destroy`**: keep it `false` outside dev. With versioning on,
  a destroy with `force_destroy = true` permanently deletes all versions.
