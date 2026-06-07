###############################################################################
# Outputs of the athena module
###############################################################################

output "workgroup_name" {
  description = "Athena workgroup name (select it in the console before running queries)."
  value       = aws_athena_workgroup.this.name
}

output "results_bucket_name" {
  description = "Name of the S3 bucket where Athena stores query results."
  value       = aws_s3_bucket.results.id
}

output "results_location" {
  description = "S3 URI used as the workgroup's default output location."
  value       = "s3://${aws_s3_bucket.results.id}/query-results/"
}
