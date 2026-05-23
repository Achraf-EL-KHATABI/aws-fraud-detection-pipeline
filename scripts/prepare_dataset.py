#!/usr/bin/env python3
"""
prepare_dataset.py  (v2 — fraud-aware windowing)
================================================
Prepare a partitioned 7-day sample of the IBM TabFormer credit card
transaction dataset, choosing the 7-day window that is RICHEST IN FRAUD.

Why v2?
-------
Fraud in this dataset is rare (~0.12%) and unevenly spread across the year.
v1 picked the densest window by *volume*, which can land on a fraud-free
week. v2 instead scans candidate years, counts fraud per day, and selects
the contiguous 7-day window containing the MOST fraud — guaranteeing the
sample has real fraud to validate detection rules against.

Pipeline
--------
  1. EXPLORE : stream the file once, counting per (year, month, day):
               total rows AND fraud rows.
  2. PICK    : among the candidate years, find the contiguous 7-day window
               with the highest fraud count.
  3. EXTRACT : stream again, keep ALL rows of that window, clean them, keep
               every fraud + down-sample legit rows to the target volume.
  4. PARTITION: write one CSV per day under
               output/transactions/year=YYYY/month=MM/day=DD/part.csv

Memory-safe: chunked reads, never loads the full 2.4 GB at once.

Usage
-----
    python prepare_dataset.py \
        --input  card_transaction.v1.csv \
        --output ./output \
        --target 200000 \
        --candidate-years 2010 2008 2016 2015 2018
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict

import pandas as pd

USECOLS = [
    "User", "Card", "Year", "Month", "Day", "Time", "Amount",
    "Use Chip", "Merchant Name", "Merchant City", "Merchant State",
    "MCC", "Is Fraud?",
]

RENAME = {
    "User": "user_id",
    "Card": "card_id",
    "Year": "year",
    "Month": "month",
    "Day": "day",
    "Time": "time",
    "Amount": "amount",
    "Use Chip": "use_chip",
    "Merchant Name": "merchant_id",
    "Merchant City": "merchant_city",
    "Merchant State": "merchant_state",
    "MCC": "mcc",
    "Is Fraud?": "is_fraud",
}

CHUNK = 500_000


def explore(input_path: str, years: set[int]):
    """Pass 1: per (year, month, day) -> (total_rows, fraud_rows)."""
    print(f"[explore] scanning daily totals + fraud for years {sorted(years)} ...")
    total: dict[tuple[int, int, int], int] = defaultdict(int)
    fraud: dict[tuple[int, int, int], int] = defaultdict(int)
    seen = 0

    reader = pd.read_csv(
        input_path,
        usecols=["Year", "Month", "Day", "Is Fraud?"],
        chunksize=CHUNK,
    )
    for i, chunk in enumerate(reader):
        sub = chunk[chunk["Year"].isin(years)]
        if not sub.empty:
            is_fraud = sub["Is Fraud?"].astype(str).str.strip() == "Yes"
            for (y, m, d), n in sub.groupby(["Year", "Month", "Day"]).size().items():
                total[(int(y), int(m), int(d))] += int(n)
            for (y, m, d), n in sub[is_fraud].groupby(["Year", "Month", "Day"]).size().items():
                fraud[(int(y), int(m), int(d))] += int(n)
        seen += len(chunk)
        if (i + 1) % 10 == 0:
            print(f"  ... scanned {seen:,} rows")

    print(f"[explore] done. {len(total)} distinct days across candidate years.")
    return total, fraud


def pick_fraud_window(total, fraud, days: int = 7):
    """Find the contiguous N-day window (within one month) richest in fraud."""
    # group days by (year, month)
    by_ym: dict[tuple[int, int], list[int]] = defaultdict(list)
    for (y, m, d) in total:
        by_ym[(y, m)].append(d)

    best = None  # (fraud_count, total_count, year, month, [days])
    for (y, m), dlist in by_ym.items():
        dlist.sort()
        dayset = set(dlist)
        for start in dlist:
            window = [start + k for k in range(days)]
            if all(d in dayset for d in window):
                f = sum(fraud.get((y, m, d), 0) for d in window)
                t = sum(total.get((y, m, d), 0) for d in window)
                if best is None or f > best[0]:
                    best = (f, t, y, m, window)

    if best is None:
        sys.exit("[pick] No contiguous 7-day window found. Add more candidate years.")

    f, t, y, m, window = best
    print(f"[pick] richest window = {y}-{m:02d}-{window[0]:02d}..{window[-1]:02d} "
          f"-> {f:,} frauds among {t:,} rows")
    if f == 0:
        print("[pick] WARNING: best window still has 0 fraud. "
              "Try different --candidate-years.")
    return y, m, window


def clean_chunk(df: pd.DataFrame) -> pd.DataFrame:
    df = df.rename(columns=RENAME)
    df["amount"] = (
        df["amount"].astype(str).str.replace("$", "", regex=False).astype(float)
    )
    df["is_fraud"] = (df["is_fraud"].astype(str).str.strip() == "Yes").astype(int)
    return df


def extract(input_path: str, year: int, month: int, window: list[int], target: int):
    print(f"[extract] extracting {year}-{month:02d}-{window} ...")
    frauds, legits = [], []
    reader = pd.read_csv(input_path, usecols=USECOLS, chunksize=CHUNK)
    for chunk in reader:
        sub = chunk[
            (chunk["Year"] == year)
            & (chunk["Month"] == month)
            & (chunk["Day"].isin(window))
        ]
        if sub.empty:
            continue
        sub = clean_chunk(sub)
        frauds.append(sub[sub["is_fraud"] == 1])
        legits.append(sub[sub["is_fraud"] == 0])

    fraud_df = pd.concat(frauds, ignore_index=True) if frauds else pd.DataFrame()
    legit_df = pd.concat(legits, ignore_index=True) if legits else pd.DataFrame()

    n_fraud = len(fraud_df)
    n_legit_target = max(target - n_fraud, 0)
    if len(legit_df) > n_legit_target:
        legit_df = legit_df.sample(n=n_legit_target, random_state=42)

    result = pd.concat([fraud_df, legit_df], ignore_index=True)
    result = result.sort_values(["day", "time"]).reset_index(drop=True)
    print(f"[extract] kept {n_fraud:,} fraud + {len(legit_df):,} legit "
          f"= {len(result):,} rows")
    return result


def write_partitions(df: pd.DataFrame, output_dir: str) -> None:
    base = os.path.join(output_dir, "transactions")
    written = 0
    for (y, m, d), part in df.groupby(["year", "month", "day"]):
        path = os.path.join(base, f"year={y:04d}", f"month={m:02d}", f"day={d:02d}")
        os.makedirs(path, exist_ok=True)
        out = os.path.join(path, "part.csv")
        part.to_csv(out, index=False)
        written += 1
        print(f"  wrote {out}  ({len(part):,} rows, {int(part['is_fraud'].sum())} fraud)")
    print(f"[write] {written} daily partitions under {base}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", default="./output")
    ap.add_argument("--target", type=int, default=200_000)
    ap.add_argument(
        "--candidate-years", type=int, nargs="+",
        default=[2010, 2008, 2016, 2015, 2018],
        help="Years to scan for the richest fraud window (from diagnose_fraud.py).",
    )
    args = ap.parse_args()

    if not os.path.isfile(args.input):
        sys.exit(f"Input file not found: {args.input}")

    total, fraud = explore(args.input, set(args.candidate_years))
    year, month, window = pick_fraud_window(total, fraud, days=7)
    df = extract(args.input, year, month, window, args.target)

    if df.empty:
        sys.exit("[main] No rows extracted — aborting.")

    write_partitions(df, args.output)

    fraud_rate = 100 * df["is_fraud"].mean()
    print("\n==================== SUMMARY ====================")
    print(f"Total rows      : {len(df):,}")
    print(f"Fraud rows      : {int(df['is_fraud'].sum()):,} ({fraud_rate:.3f}%)")
    print(f"Window          : {year}-{month:02d}-{window[0]:02d}..{window[-1]:02d}")
    print(f"Output dir      : {os.path.join(args.output, 'transactions')}")
    print("=================================================")


if __name__ == "__main__":
    main()
