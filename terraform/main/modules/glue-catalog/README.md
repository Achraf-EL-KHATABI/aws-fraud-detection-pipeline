# Module `glue-catalog`

Provisions the AWS Glue Data Catalog database and the Glue Crawler that
auto-discovers Parquet tables in the curated zone of the data lake.

## What it creates

- **`aws_glue_catalog_database`** — logical container named `fraud_detection`
- **`aws_iam_role`** — assumed by the Crawler (Glue service principal only)
- **`aws_iam_policy`** — scoped: read curated bucket + manage tables in OUR
  database only (no blanket `glue:*` or `s3:*`)
- **`aws_glue_crawler`** — scans `s3://<curated_bucket>/transactions/`,
  creates one table per detected schema, registers Hive partitions

## Usage

```hcl
module "glue_catalog" {
  source = "./modules/glue-catalog"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  aws_region  = var.aws_region

  curated_bucket_name = module.s3_datalake.curated_bucket_name
  curated_bucket_arn  = module.s3_datalake.curated_bucket_arn

  tags = local.common_tags
}
```

## Running the crawler

The Crawler is **not scheduled** — we run it on demand:

```bash
aws glue start-crawler \
    --name fraud-detection-dev-curated-crawler \
    --profile project-profile --region eu-west-3
```

Once it succeeds, a new table `transactions` appears in the
`fraud_detection` database. Athena can query it immediately.

## Design notes

- `SchemaChangePolicy = LOG` (delete) prevents the Crawler from removing
  tables when partitions disappear temporarily.
- `CombineCompatibleSchemas` groups the multiple `part-XXXXX` Parquet files
  written by Spark under one logical table.
- Adding a schedule (`schedule = "cron(0 3 * * ? *)"`) is one line away if
  we later move from on-demand to recurring.
