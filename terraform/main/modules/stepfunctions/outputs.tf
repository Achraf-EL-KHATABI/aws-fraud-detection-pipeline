###############################################################################
# Outputs of the stepfunctions module
###############################################################################

output "state_machine_arn" {
  description = "ARN of the orchestrator state machine. Used by EventBridge (next sub-step)."
  value       = aws_sfn_state_machine.orchestrator.arn
}

output "state_machine_name" {
  description = "Name of the state machine (handy for `aws stepfunctions start-execution`)."
  value       = aws_sfn_state_machine.orchestrator.name
}

output "state_machine_role_arn" {
  description = "ARN of the IAM role assumed by the state machine."
  value       = aws_iam_role.state_machine.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group holding state-machine execution traces."
  value       = aws_cloudwatch_log_group.state_machine.name
}
