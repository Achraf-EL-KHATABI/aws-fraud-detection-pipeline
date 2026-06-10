###############################################################################
# Outputs of the eventbridge module
###############################################################################

output "rule_name" {
  description = "Name of the EventBridge daily rule."
  value       = aws_cloudwatch_event_rule.daily.name
}

output "rule_arn" {
  description = "ARN of the EventBridge daily rule."
  value       = aws_cloudwatch_event_rule.daily.arn
}

output "schedule_expression" {
  description = "Effective cron expression applied to the rule."
  value       = aws_cloudwatch_event_rule.daily.schedule_expression
}

output "rule_enabled" {
  description = "Whether the rule is currently active."
  value       = aws_cloudwatch_event_rule.daily.state == "ENABLED"
}
