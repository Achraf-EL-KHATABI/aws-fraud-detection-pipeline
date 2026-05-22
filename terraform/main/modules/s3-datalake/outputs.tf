###############################################################################
# Outputs of the s3-datalake module
#
# These expose the created buckets so the rest of the stack (Glue job,
# Athena, Step Functions, IAM policies...) can reference them by ARN or name
# WITHOUT hardcoding strings. This is how modules compose cleanly.
#
# Because we used for_each, the resources are maps keyed by zone name.
# We re-shape them into convenient output maps below.
###############################################################################

output "bucket_names" {
  description = "Map of zone => bucket name (e.g. raw => fraud-detection-dev-raw-424414904672)."
  value       = { for zone, b in aws_s3_bucket.this : zone => b.id }
}

output "bucket_arns" {
  description = "Map of zone => bucket ARN. Used by IAM policies for least-privilege access."
  value       = { for zone, b in aws_s3_bucket.this : zone => b.arn }
}

output "bucket_domain_names" {
  description = "Map of zone => regional domain name. Useful for some service integrations."
  value       = { for zone, b in aws_s3_bucket.this : zone => b.bucket_regional_domain_name }
}

# Convenience single-value outputs for the most-used buckets, so callers can
# write module.s3_datalake.raw_bucket_arn instead of the map lookup syntax.
output "raw_bucket_name" {
  description = "Name of the raw (bronze) zone bucket."
  value       = aws_s3_bucket.this["raw"].id
}

output "raw_bucket_arn" {
  description = "ARN of the raw (bronze) zone bucket."
  value       = aws_s3_bucket.this["raw"].arn
}

output "curated_bucket_name" {
  description = "Name of the curated (silver) zone bucket."
  value       = aws_s3_bucket.this["curated"].id
}

output "curated_bucket_arn" {
  description = "ARN of the curated (silver) zone bucket."
  value       = aws_s3_bucket.this["curated"].arn
}

output "analytics_bucket_name" {
  description = "Name of the analytics (gold) zone bucket."
  value       = aws_s3_bucket.this["analytics"].id
}

output "analytics_bucket_arn" {
  description = "ARN of the analytics (gold) zone bucket."
  value       = aws_s3_bucket.this["analytics"].arn
}
