# Module `stepfunctions`

Provisions the Step Functions Standard state machine that orchestrates the
daily fraud-detection batch:

```
RunGlueJob (Glue ETL, sync)  →  StartCrawler (Glue Crawler)  →  Succeeded
        │                              │
        └─ Catch → JobFailed           └─ Catch → CrawlerFailed
```

## What it creates

- **`aws_sfn_state_machine`** — Standard workflow (`<prefix>-orchestrator`)
- **`aws_iam_role`** — assumable only by `states.amazonaws.com`
- **`aws_iam_policy`** — scoped: start/monitor **our** Glue job and crawler,
  plus the EventBridge callback permissions required by the `.sync` pattern
- **`aws_cloudwatch_log_group`** — execution logs, retention configurable

## Why Standard (not Express)?

- **Express** is for high-throughput, sub-second workflows (cheaper per
  execution, but no `.sync` for long Glue jobs).
- **Standard** supports `.sync` integrations and keeps 90 days of execution
  history for free — perfect for a daily batch.

## Usage

```hcl
module "stepfunctions" {
  source = "./modules/stepfunctions"

  name_prefix = local.name_prefix
  account_id  = local.account_id
  aws_region  = var.aws_region

  glue_job_name     = module.glue.glue_job_name
  glue_crawler_name = module.glue_catalog.crawler_name

  tags = local.common_tags
}
```

## Running manually

```bash
aws stepfunctions start-execution \
    --state-machine-arn $(terraform output -raw stepfunctions_state_machine_arn) \
    --profile project-profile --region eu-west-3
```

Or in the console:
**Step Functions → State machines → `<prefix>-orchestrator` → Start execution → Start**

The graphical view lights each state green/red as the execution progresses.

## What's next

Sub-step 9.2 (next session) will add **EventBridge** to invoke this state
machine on a daily cron (e.g. `cron(0 2 * * ? *)` for 02:00 UTC).
