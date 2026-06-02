# Module `glue`

Provisions the AWS Glue ETL job that scores transactions with fraud-detection
rules and writes the result to the curated zone.

## What this module creates

**Sub-step 7.2a (this PR):**
- Uploads the local PySpark script (`glue_jobs/fraud_etl_glue.py`) to S3
- IAM role assumable only by the Glue service
- Least-privilege IAM policy: read `raw/`, read/write `curated/`, read the
  script bucket, write `/aws-glue/*` CloudWatch Logs
- AWS-managed `AWSGlueServiceRole` for standard Glue plumbing

**Sub-step 7.2b (next session):**
- The `aws_glue_job` resource itself (Glue 4.0, G.1X workers, timeout)
- Wiring of bucket names + script S3 URI as job arguments

## Usage (after both sub-steps are in)

```hcl
module "glue" {
  source = "./modules/glue"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  aws_region  = var.aws_region

  raw_bucket_name     = module.s3_datalake.raw_bucket_name
  raw_bucket_arn      = module.s3_datalake.raw_bucket_arn
  curated_bucket_name = module.s3_datalake.curated_bucket_name
  curated_bucket_arn  = module.s3_datalake.curated_bucket_arn

  script_bucket_name = module.s3_datalake.raw_bucket_name   # reuse raw for scripts
  script_bucket_arn  = module.s3_datalake.raw_bucket_arn
  script_local_path  = "${path.root}/../../glue_jobs/fraud_etl_glue.py"

  tags = local.common_tags
}
```

## Design choices

- **Script storage**: stored in the raw bucket under `glue_jobs/` for now to
  avoid creating yet another bucket. A dedicated `artifacts/` bucket is the
  classic prod pattern.
- **Least privilege**: the data-access policy is scoped to the project's
  buckets only, never `s3:*` on `*`.
- **Script change detection**: `etag = filemd5(...)` makes Terraform re-upload
  the script automatically when its content changes locally.
