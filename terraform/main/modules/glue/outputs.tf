###############################################################################
# Outputs of the `glue` module (sub-step 7.2a)
#
# The job resource (sub-step 7.2b) will reference these outputs internally,
# and the main project may surface them for inspection or use in other
# modules (e.g. the Step Functions module will need the job name later).
###############################################################################

output "glue_role_arn" {
  description = "ARN of the IAM role assumed by the Glue ETL job."
  value       = aws_iam_role.glue_job.arn
}

output "glue_role_name" {
  description = "Name of the IAM role assumed by the Glue ETL job."
  value       = aws_iam_role.glue_job.name
}

output "script_s3_uri" {
  description = "S3 URI where the Glue Job will read its PySpark script from."
  value       = "s3://${var.script_bucket_name}/${aws_s3_object.fraud_etl_script.key}"
}


output "glue_job_name" {
  description = "Name of the Glue ETL job. Used to start it from the CLI or Step Functions."
  value       = aws_glue_job.fraud_etl.name
}

output "glue_job_arn" {
  description = "ARN of the Glue ETL job."
  value       = aws_glue_job.fraud_etl.arn
}

