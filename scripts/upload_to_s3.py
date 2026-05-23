#!/usr/bin/env python3
"""
upload_to_s3.py
===============
Upload the partitioned transaction dataset to the S3 *raw* zone of the
fraud-detection data lake.

It walks a local directory that follows the Hive-style partition layout:

    <local_dir>/transactions/year=YYYY/month=MM/day=DD/part.csv

and uploads each file to the same key path under an S3 prefix:

    s3://<bucket>/transactions/year=YYYY/month=MM/day=DD/part.csv

This Hive layout (key=value folders) is what the Glue Crawler will later
auto-detect as partition columns — so we preserve it exactly.

Design notes
------------
- Uses a NAMED AWS profile (same `project-profile` used by Terraform), so it
  authenticates exactly like the rest of the project. No keys in code.
- `--dry-run` lists what *would* be uploaded without sending anything — always
  run it first.
- Skips non-CSV files defensively.
- Sets Content-Type and a small set of metadata tags on each object.
- Prints a clear per-file log and a final summary.

Usage
-----
    # 1) Always dry-run first
    python upload_to_s3.py \
        --local  "C:/Users/acelk/Desktop/projects/_datasets/prepared" \
        --bucket fraud-detection-dev-raw-424414904672 \
        --profile project-profile \
        --region eu-west-3 \
        --dry-run

    # 2) Then the real upload
    python upload_to_s3.py \
        --local  "C:/Users/acelk/Desktop/projects/_datasets/prepared" \
        --bucket fraud-detection-dev-raw-424414904672 \
        --profile project-profile \
        --region eu-west-3
"""

from __future__ import annotations

import argparse
import os
import sys

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError, ProfileNotFound
except ImportError:
    sys.exit("boto3 is not installed. Run:  pip install boto3")


def find_csv_files(local_root: str) -> list[str]:
    """Return all .csv files under <local_root>/transactions/."""
    base = os.path.join(local_root, "transactions")
    if not os.path.isdir(base):
        sys.exit(f"Expected a 'transactions/' folder under {local_root}. Not found.")

    files = []
    for dirpath, _dirs, filenames in os.walk(base):
        for fn in filenames:
            if fn.lower().endswith(".csv"):
                files.append(os.path.join(dirpath, fn))
    return sorted(files)


def to_s3_key(local_path: str, local_root: str) -> str:
    """Convert a local file path into the S3 key, preserving partitions.

    Local : <local_root>/transactions/year=2015/month=12/day=17/part.csv
    Key   : transactions/year=2015/month=12/day=17/part.csv
    """
    rel = os.path.relpath(local_path, local_root)
    # Normalise Windows backslashes to forward slashes for S3
    return rel.replace(os.sep, "/")


def human_size(num_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if num_bytes < 1024:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:.1f} TB"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--local", required=True,
                    help="Local root containing the 'transactions/' folder.")
    ap.add_argument("--bucket", required=True, help="Target S3 bucket (raw zone).")
    ap.add_argument("--profile", default="project-profile",
                    help="AWS CLI named profile to authenticate with.")
    ap.add_argument("--region", default="eu-west-3", help="AWS region.")
    ap.add_argument("--dry-run", action="store_true",
                    help="List planned uploads without sending anything.")
    args = ap.parse_args()

    files = find_csv_files(args.local)
    if not files:
        sys.exit("No CSV files found to upload.")

    total_bytes = sum(os.path.getsize(f) for f in files)
    print(f"Found {len(files)} CSV file(s), {human_size(total_bytes)} total.")
    print(f"Target: s3://{args.bucket}/  (region {args.region})")
    print("-" * 70)

    # --- DRY RUN: just print the plan -------------------------------------
    if args.dry_run:
        for f in files:
            key = to_s3_key(f, args.local)
            print(f"[dry-run] {human_size(os.path.getsize(f)):>9}  ->  s3://{args.bucket}/{key}")
        print("-" * 70)
        print("[dry-run] Nothing was uploaded. Re-run without --dry-run to upload.")
        return

    # --- REAL UPLOAD ------------------------------------------------------
    try:
        session = boto3.Session(profile_name=args.profile, region_name=args.region)
        s3 = session.client("s3")
    except ProfileNotFound:
        sys.exit(f"AWS profile '{args.profile}' not found. Check ~/.aws/credentials.")

    # Sanity check: confirm the bucket exists and we can access it.
    try:
        s3.head_bucket(Bucket=args.bucket)
    except (ClientError, NoCredentialsError) as e:
        sys.exit(f"Cannot access bucket '{args.bucket}': {e}")

    uploaded, failed = 0, 0
    for f in files:
        key = to_s3_key(f, args.local)
        try:
            s3.upload_file(
                Filename=f,
                Bucket=args.bucket,
                Key=key,
                ExtraArgs={
                    "ContentType": "text/csv",
                    "Metadata": {
                        "source": "ibm-tabformer",
                        "pipeline-zone": "raw",
                    },
                },
            )
            print(f"  uploaded  s3://{args.bucket}/{key}")
            uploaded += 1
        except ClientError as e:
            print(f"  FAILED    {key}: {e}")
            failed += 1

    print("-" * 70)
    print(f"Done. {uploaded} uploaded, {failed} failed.")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
