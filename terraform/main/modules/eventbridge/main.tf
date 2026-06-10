###############################################################################
# eventbridge module — daily cron trigger for the orchestrator
#
# Creates:
#   1. aws_iam_role           — assumed by EventBridge to start the state machine
#   2. aws_iam_policy         — least-privilege: start execution on OUR machine
#   3. aws_cloudwatch_event_rule  — the cron schedule
#   4. aws_cloudwatch_event_target — wires the rule to the state machine
#
# Note on naming:
#   We use the classic `cloudwatch_event_*` resources (a.k.a. EventBridge
#   Rules). AWS also has a newer service called "EventBridge Scheduler"
#   (aws_scheduler_schedule) — both work, but Rules are widely battle-tested
#   and well-supported by Terraform, with simpler IAM.
###############################################################################

# -----------------------------------------------------------------------------
# 1. IAM trust + permissions for EventBridge
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "events_assume_role" {
  statement {
    sid     = "AllowEventBridgeToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = "${var.name_prefix}-eventbridge-trigger"
  description        = "Role assumed by EventBridge to start the daily state machine execution."
  assume_role_policy = data.aws_iam_policy_document.events_assume_role.json

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-eventbridge-trigger"
    Component = "eventbridge"
  })
}

# Least-privilege: this role can only start executions on the ONE state
# machine we hand it. No states:* wildcard.
data "aws_iam_policy_document" "events_permissions" {
  statement {
    sid    = "StartTargetStateMachine"
    effect = "Allow"
    actions = [
      "states:StartExecution",
    ]
    resources = [var.state_machine_arn]
  }
}

resource "aws_iam_policy" "events_permissions" {
  name        = "${var.name_prefix}-eventbridge-trigger-perms"
  description = "Allows EventBridge to start the orchestrator state machine."
  policy      = data.aws_iam_policy_document.events_permissions.json
}

resource "aws_iam_role_policy_attachment" "events_permissions" {
  role       = aws_iam_role.events.name
  policy_arn = aws_iam_policy.events_permissions.arn
}

# -----------------------------------------------------------------------------
# 2. The cron rule
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${var.name_prefix}-daily-batch"
  description         = "Daily trigger for the fraud-detection orchestrator state machine."
  schedule_expression = var.schedule_expression
  state               = var.enabled ? "ENABLED" : "DISABLED"

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-daily-batch"
    Component = "eventbridge"
  })
}

# -----------------------------------------------------------------------------
# 3. Wire the rule to the state machine as its target
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "state_machine" {
  rule     = aws_cloudwatch_event_rule.daily.name
  arn      = var.state_machine_arn
  role_arn = aws_iam_role.events.arn

  # Static input to the state machine; we don't need anything dynamic for now.
  input = jsonencode({
    triggered_by = "eventbridge-daily-cron"
  })
}
