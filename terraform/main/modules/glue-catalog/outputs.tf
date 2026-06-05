###############################################################################
# Outputs of the glue-catalog module
###############################################################################

output "database_name" {
  description = "Name of the Glue Catalog database (used by Athena queries)."
  value       = aws_glue_catalog_database.this.name
}

output "crawler_name" {
  description = "Name of the Glue Crawler (start it with `aws glue start-crawler --name ...`)."
  value       = aws_glue_crawler.curated.name
}

output "crawler_role_arn" {
  description = "ARN of the IAM role assumed by the Crawler."
  value       = aws_iam_role.crawler.arn
}
