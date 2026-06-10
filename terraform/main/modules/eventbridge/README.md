# Module `eventbridge`

Provisions the EventBridge Rule that triggers the orchestrator state machine
on a daily cron, plus the IAM role EventBridge assumes for that.

## What it creates

- **`aws_cloudwatch_event_rule`** — the cron schedule (default: 02:00 UTC daily)
- **`aws_cloudwatch_event_target`** — wires the rule to the state machine
- **`aws_iam_role`** — assumable only by `events.amazonaws.com`
- **`aws_iam_policy`** — least-privilege: `states:StartExecution` on the
  target machine ARN only (no `states:*` wildcard)

## Usage

```hcl
module "eventbridge" {
  source = "./modules/eventbridge"

  name_prefix       = local.name_prefix
  state_machine_arn = module.stepfunctions.state_machine_arn

  # Default = "cron(0 2 * * ? *)" — daily at 02:00 UTC.
  # Override examples:
  #   "cron(0 6 ? * MON-FRI *)"   business days at 06:00 UTC
  #   "rate(15 minutes)"          every 15 min (handy for demos)
  enabled = true

  tags = local.common_tags
}
```

## Cron syntax (EventBridge)

EventBridge uses a **6-field** cron: `cron(minute hour day-of-month month day-of-week year)`.
At least one of *day-of-month* and *day-of-week* must be `?` (placeholder).

| Expression                | Meaning                          |
|---------------------------|----------------------------------|
| `cron(0 2 * * ? *)`       | Every day at 02:00 UTC           |
| `cron(0 2 ? * MON-FRI *)` | Business days at 02:00 UTC       |
| `cron(0/15 * * * ? *)`    | Every 15 minutes                 |

## Disable temporarily

Set `enabled = false` and re-apply. The rule stays in place but stops firing
until re-enabled — handy to pause the pipeline without destroying it.
