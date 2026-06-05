###############################################################################
# glue-catalog module — Data Catalog + Crawler
#
# Creates:
#   1. aws_glue_catalog_database  — logical container for tables.
#   2. aws_iam_role               — identity the Crawler assumes when running.
#   3. aws_iam_policy             — scoped permissions: read curated bucket
#                                   + manage tables in OUR database only.
#   4. aws_glue_crawler           — the robot that scans S3 and creates the
#                                   table + partitions automatically.
#
# Design choices:
#   - The Crawler is NOT scheduled. We run it on-demand (after each Glue Job
#     output). Adding a schedule is trivial later if we want.
#   - SchemaChangePolicy = LOG: if the schema changes between runs, the
#     Crawler logs it rather than failing. Safer for an evolving pipeline.
#   - The Crawler's path includes the source_prefix so it doesn't try to
#     scan _glue_temp/ or any other folder we might create later.
###############################################################################

# -----------------------------------------------------------------------------
# 1. The catalog database
# -----------------------------------------------------------------------------
resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "Glue Catalog database for the fraud-detection pipeline (Athena/QuickSight read from here)."
}

# -----------------------------------------------------------------------------
# 2. IAM trust policy: only the Glue service can assume this role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "crawler_assume_role" {
  statement {
    sid     = "AllowGlueToAssumeCrawlerRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crawler" {
  name               = "${var.name_prefix}-glue-crawler"
  description        = "Role assumed by the Glue Crawler that catalogs the curated zone."
  assume_role_policy = data.aws_iam_policy_document.crawler_assume_role.json

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-glue-crawler"
    Component = "glue-catalog"
  })
}

# AWS-managed service role for Crawlers (Glue API + CloudWatch Logs).
resource "aws_iam_role_policy_attachment" "crawler_managed" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# -----------------------------------------------------------------------------
# 3. Custom least-privilege policy: read curated + manage our database only
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "crawler_data_access" {
  # Read the curated bucket (where the Parquet sits).
  statement {
    sid    = "ReadCuratedZone"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.curated_bucket_arn,
      "${var.curated_bucket_arn}/*",
    ]
  }

  # The Crawler needs to create/update tables and partitions in OUR database.
  # Scoping to our specific database (and its tables) avoids granting
  # blanket glue:* across the account.
  statement {
    sid    = "ManageOwnTables"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:BatchUpdatePartition",
      "glue:CreatePartition",
      "glue:UpdatePartition",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.aws_region}:${var.account_id}:database/${var.database_name}",
      "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.database_name}/*",
    ]
  }
}

resource "aws_iam_policy" "crawler_data_access" {
  name        = "${var.name_prefix}-glue-crawler-access"
  description = "Least-privilege S3 read + Glue catalog write for the curated crawler."
  policy      = data.aws_iam_policy_document.crawler_data_access.json
}

resource "aws_iam_role_policy_attachment" "crawler_data_access" {
  role       = aws_iam_role.crawler.name
  policy_arn = aws_iam_policy.crawler_data_access.arn
}

# -----------------------------------------------------------------------------
# 4. The Crawler itself
# -----------------------------------------------------------------------------
resource "aws_glue_crawler" "curated" {
  name          = "${var.name_prefix}-curated-crawler"
  description   = "Auto-discovers Parquet tables and partitions in the curated zone."
  database_name = aws_glue_catalog_database.this.name
  role          = aws_iam_role.crawler.arn

  # Scan only the transactions/ prefix — avoids touching _glue_temp/ etc.
  s3_target {
    path = "s3://${var.curated_bucket_name}/${var.source_prefix}/"
  }

  # On schema change: log it, don't fail. On deletion: log and proceed.
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  # CrawlerOutput: how it organises what it finds. With CombineCompatibleSchemas,
  # all part-XXXXX.snappy.parquet under a partition are merged into one table.
  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-curated-crawler"
    Component = "glue-catalog"
  })
}
