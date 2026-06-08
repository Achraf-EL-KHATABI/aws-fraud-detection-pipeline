###############################################################################
# stepfunctions module — orchestration of the daily batch
#
# Creates a Step Functions Standard state machine that:
#   1. Starts the Glue ETL job (sync — waits for the job to finish).
#   2. Starts the Crawler so Athena sees any new partitions.
#
# Why "Standard" workflow type (not Express)?
#   - Express is cheaper and for sub-second high-throughput workflows.
#   - Standard supports long-running tasks (.sync), which we need for
#     the Glue job (up to 30 min). It also keeps execution history for
#     90 days for free, useful for debugging.
###############################################################################

# -----------------------------------------------------------------------------
# 1. IAM trust + permissions for Step Functions
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    sid     = "AllowStepFunctionsToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name               = "${var.name_prefix}-sfn-orchestrator"
  description        = "Role assumed by the daily fraud-detection state machine."
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-sfn-orchestrator"
    Component = "stepfunctions"
  })
}

# Least-privilege policy: start/monitor only OUR Glue job + crawler,
# and write to OUR CloudWatch log group.
data "aws_iam_policy_document" "sfn_permissions" {
  # ---- Trigger and monitor the Glue ETL job ------------------------------
  statement {
    sid    = "RunGlueJob"
    effect = "Allow"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${var.account_id}:job/${var.glue_job_name}",
    ]
  }

  # ---- Trigger the Crawler -----------------------------------------------
  statement {
    sid    = "RunGlueCrawler"
    effect = "Allow"
    actions = [
      "glue:StartCrawler",
      "glue:GetCrawler",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${var.account_id}:crawler/${var.glue_crawler_name}",
    ]
  }

  # ---- Step Functions managed-rule callback (needed by .sync pattern) ----
  # The .sync integration uses an EventBridge managed rule to receive Glue
  # state changes. This permission is documented and required.
  statement {
    sid    = "EventBridgeCallback"
    effect = "Allow"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule",
    ]
    resources = [
      "arn:aws:events:${var.aws_region}:${var.account_id}:rule/StepFunctionsGetEventsForGlueJobRule",
    ]
  }

  # ---- CloudWatch Logs for the state machine ------------------------------
  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sfn_permissions" {
  name        = "${var.name_prefix}-sfn-orchestrator-perms"
  description = "Least-privilege permissions for the fraud-detection state machine."
  policy      = data.aws_iam_policy_document.sfn_permissions.json
}

resource "aws_iam_role_policy_attachment" "sfn_permissions" {
  role       = aws_iam_role.state_machine.name
  policy_arn = aws_iam_policy.sfn_permissions.arn
}

# -----------------------------------------------------------------------------
# 2. CloudWatch Log Group for state machine executions
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/vendedlogs/states/${var.name_prefix}-orchestrator"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Component = "stepfunctions"
  })
}

# -----------------------------------------------------------------------------
# 3. The state machine itself
# -----------------------------------------------------------------------------
# The ASL definition lives in state_machine.json.tpl with two placeholders
# (${glue_job_name}, ${glue_crawler_name}) that we substitute via templatefile().
resource "aws_sfn_state_machine" "orchestrator" {
  name     = "${var.name_prefix}-orchestrator"
  role_arn = aws_iam_role.state_machine.arn
  type     = "STANDARD"

  definition = templatefile("${path.module}/state_machine.json.tpl", {
    glue_job_name     = var.glue_job_name
    glue_crawler_name = var.glue_crawler_name
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-orchestrator"
    Component = "stepfunctions"
  })
}
