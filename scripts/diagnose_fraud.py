#!/usr/bin/env python3
"""
diagnose_fraud.py
=================
Quick diagnostic to understand the fraud distribution in the TabFormer
dataset before sampling. Answers two questions:

  1. Does the "Is Fraud?" column parse correctly? (prints its unique values)
  2. How many frauds exist per year? (so we sample from a fraud-rich year)

Streams in chunks — memory-safe on the 2.4 GB file.

Usage:
    python diagnose_fraud.py --input card_transaction.v1.csv
"""
from __future__ import annotations

import argparse
import sys
from collections import defaultdict

import pandas as pd

CHUNK = 500_000


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    args = ap.parse_args()

    fraud_by_year: dict[int, int] = defaultdict(int)
    total_by_year: dict[int, int] = defaultdict(int)
    unique_flags: set[str] = set()
    seen = 0

    reader = pd.read_csv(
        args.input,
        usecols=["Year", "Is Fraud?"],
        chunksize=CHUNK,
    )
    for i, chunk in enumerate(reader):
        # capture the raw distinct values of the fraud flag (first few chunks)
        if i < 3:
            unique_flags.update(chunk["Is Fraud?"].astype(str).str.strip().unique())

        is_fraud = chunk["Is Fraud?"].astype(str).str.strip() == "Yes"
        for y, n in chunk.groupby("Year").size().items():
            total_by_year[int(y)] += int(n)
        for y, n in chunk[is_fraud].groupby("Year").size().items():
            fraud_by_year[int(y)] += int(n)

        seen += len(chunk)
        if (i + 1) % 10 == 0:
            print(f"  ... scanned {seen:,} rows")

    print("\nUnique values in 'Is Fraud?':", sorted(unique_flags))
    print("\nYear      Total        Fraud      Fraud%")
    print("-" * 45)
    for y in sorted(total_by_year):
        tot = total_by_year[y]
        fr = fraud_by_year.get(y, 0)
        pct = 100 * fr / tot if tot else 0
        print(f"{y}   {tot:>12,}   {fr:>8,}   {pct:>7.4f}%")

    total_fraud = sum(fraud_by_year.values())
    total_all = sum(total_by_year.values())
    print("-" * 45)
    print(f"TOTAL   {total_all:>12,}   {total_fraud:>8,}   "
          f"{100*total_fraud/total_all:.4f}%")

    # recommend the best years (most frauds)
    best = sorted(fraud_by_year.items(), key=lambda kv: kv[1], reverse=True)[:5]
    print("\nTop 5 fraud-rich years:")
    for y, fr in best:
        print(f"  {y}: {fr:,} frauds")


if __name__ == "__main__":
    main()
