#!/usr/bin/env python3
"""
fraud_etl_glue.py
=================
AWS Glue (PySpark) ETL job for the fraud-detection pipeline.

Flow
----
    s3://<raw_bucket>/transactions/year=/month=/day=/part.csv   (input)
        -> read + parse + type
        -> apply 3 fraud-detection rules (validated in pandas first)
        -> compute composite risk score + risk level
    s3://<curated_bucket>/transactions/year=/month=/day=/...    (output, Parquet)

The rule logic mirrors scripts/fraud_rules_local.py exactly. It was
prototyped and calibrated in pandas against real data distributions before
being ported here, so the business logic is already proven.

Rules (calibrated from observed distributions)
----------------------------------------------
  R1 amount_anomaly : amount > (card mean + 3*std)  OR  amount > $300
  R2 velocity       : > 130 txns for the card within the same hour
  R4 odd_hour       : transaction in 00:00-05:00 AND amount in the top decile
  (R3 geo was dropped: changing state is normal in this dataset, not fraud.)

Composite score: 2*R1 + 1*R2 + 1*R4  ->  HIGH(>=3)/MEDIUM(>=1.5)/LOW(<1.5)

Glue job parameters (passed via --arguments)
---------------------------------------------
  --JOB_NAME        (provided automatically by Glue)
  --raw_bucket      e.g. fraud-detection-dev-raw-424414904672
  --curated_bucket  e.g. fraud-detection-dev-curated-424414904672
  --source_prefix   default: transactions
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql import Window
from pyspark.sql.types import IntegerType

# ---- Calibrated rule parameters (kept in sync with the pandas prototype) ---
ABS_AMOUNT_THRESHOLD = 300.0
AMOUNT_STD_FACTOR = 3.0
VELOCITY_MAX_PER_HOUR = 130
ODD_HOUR_START = 0
ODD_HOUR_END = 5
ODD_HOUR_AMOUNT_QUANTILE = 0.90

W_AMOUNT = 2.0
W_VELOCITY = 1.0
W_ODD_HOUR = 1.0


def main():
    # ------------------------------------------------------------------ setup
    args = getResolvedOptions(
        sys.argv,
        ["JOB_NAME", "raw_bucket", "curated_bucket", "source_prefix"],
    )
    sc = SparkContext()
    glue_context = GlueContext(sc)
    spark = glue_context.spark_session
    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)

    raw_bucket = args["raw_bucket"]
    curated_bucket = args["curated_bucket"]
    source_prefix = args.get("source_prefix", "transactions")

    input_path = f"s3://{raw_bucket}/{source_prefix}/"
    output_path = f"s3://{curated_bucket}/{source_prefix}/"

    print(f"[glue] reading from {input_path}")

    # ------------------------------------------------------------------- read
    # Hive-partitioned CSV: Spark auto-discovers year/month/day from the path
    # when basePath points at the root and we read with the partition columns.
    df = (
        spark.read
        .option("header", "true")
        .option("inferSchema", "true")
        .csv(input_path)
    )

    # The partition columns (year/month/day) are already inside the CSV files
    # too (we wrote them as data columns), so no extra handling needed.
    print(f"[glue] loaded {df.count():,} rows")

    # --------------------------------------------------------------- build ts
    # Compose a timestamp from year/month/day + the HH:MM `time` string.
    df = df.withColumn(
        "event_ts",
        F.to_timestamp(
            F.concat_ws(
                " ",
                F.concat_ws("-",
                            F.col("year").cast("string"),
                            F.lpad(F.col("month").cast("string"), 2, "0"),
                            F.lpad(F.col("day").cast("string"), 2, "0")),
                F.col("time"),
            ),
            "yyyy-MM-dd HH:mm",
        ),
    )

    # ------------------------------------------------------------ R1 amount
    # Per-card mean + std via a window over card_id.
    card_win = Window.partitionBy("card_id")
    df = df.withColumn("card_mean", F.avg("amount").over(card_win))
    df = df.withColumn("card_std", F.coalesce(F.stddev("amount").over(card_win),
                                              F.lit(0.0)))
    df = df.withColumn(
        "r1_amount_anomaly",
        ((F.col("amount") > (F.col("card_mean") + AMOUNT_STD_FACTOR * F.col("card_std")))
         | (F.col("amount") > ABS_AMOUNT_THRESHOLD)).cast(IntegerType()),
    )

    # ------------------------------------------------------------ R2 velocity
    # Count txns per card within the same truncated hour.
    df = df.withColumn("hour_bucket", F.date_trunc("hour", F.col("event_ts")))
    hour_win = Window.partitionBy("card_id", "hour_bucket")
    df = df.withColumn("txn_in_hour", F.count(F.lit(1)).over(hour_win))
    df = df.withColumn(
        "r2_velocity",
        (F.col("txn_in_hour") > VELOCITY_MAX_PER_HOUR).cast(IntegerType()),
    )

    # ------------------------------------------------------------ R4 odd hour
    # High-amount threshold = global top-decile of amount.
    high_amt = df.approxQuantile("amount", [ODD_HOUR_AMOUNT_QUANTILE], 0.01)[0]
    hour_of_day = F.hour(F.col("event_ts"))
    df = df.withColumn(
        "r4_odd_hour",
        (((hour_of_day >= ODD_HOUR_START) & (hour_of_day < ODD_HOUR_END))
         & (F.col("amount") >= F.lit(high_amt))).cast(IntegerType()),
    )

    # --------------------------------------------------------- composite score
    df = df.withColumn(
        "risk_score",
        W_AMOUNT * F.col("r1_amount_anomaly")
        + W_VELOCITY * F.col("r2_velocity")
        + W_ODD_HOUR * F.col("r4_odd_hour"),
    )
    df = df.withColumn(
        "risk_level",
        F.when(F.col("risk_score") >= 3, F.lit("HIGH"))
        .when(F.col("risk_score") >= 1.5, F.lit("MEDIUM"))
        .otherwise(F.lit("LOW")),
    )

    # Drop helper columns we don't want to persist.
    df = df.drop("card_mean", "card_std", "hour_bucket", "txn_in_hour")

    # --------------------------------------------------------------- summary
    print("[glue] risk level distribution:")
    df.groupBy("risk_level").count().show()

    # ------------------------------------------------------------------ write
    # Write Parquet, partitioned by year/month/day to mirror the raw layout.
    print(f"[glue] writing Parquet to {output_path}")
    (
        df.write
        .mode("overwrite")
        .partitionBy("year", "month", "day")
        .parquet(output_path)
    )

    print("[glue] done.")
    job.commit()


if __name__ == "__main__":
    main()
