#!/usr/bin/env python3
"""
analyze_distributions.py
========================
Inspect the real data distributions so we can calibrate fraud-rule
thresholds based on EVIDENCE rather than guesses.

Looks at:
  - transactions per card per hour  (to calibrate R2 velocity)
  - time gaps between consecutive same-card txns that change state
    (to calibrate R3 geo)
  - how frauds differ from legit on amount and these signals
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import pandas as pd


def load(input_dir: str) -> pd.DataFrame:
    files = glob.glob(os.path.join(input_dir, "**", "part.csv"), recursive=True)
    if not files:
        sys.exit(f"No part.csv under {input_dir}")
    df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)
    df["event_ts"] = pd.to_datetime(
        df["year"].astype(str) + "-"
        + df["month"].astype(str).str.zfill(2) + "-"
        + df["day"].astype(str).str.zfill(2) + " "
        + df["time"].astype(str),
        format="%Y-%m-%d %H:%M", errors="coerce",
    )
    return df.sort_values(["card_id", "event_ts"]).reset_index(drop=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    args = ap.parse_args()
    df = load(args.input)
    print(f"Loaded {len(df):,} rows, {int(df['is_fraud'].sum())} frauds\n")

    # ---- R2: transactions per card per hour --------------------------------
    tmp = df.copy()
    tmp["hour_bucket"] = tmp["event_ts"].dt.floor("h")
    per_hour = tmp.groupby(["card_id", "hour_bucket"]).size()
    print("=== Transactions per card per HOUR (for R2 velocity) ===")
    print(per_hour.describe(percentiles=[0.5, 0.9, 0.95, 0.99]).to_string())
    print(f"  % of hour-buckets with >5 txns : "
          f"{100*(per_hour > 5).mean():.1f}%")
    print(f"  % of hour-buckets with >20 txns: "
          f"{100*(per_hour > 20).mean():.1f}%")
    print(f"  % of hour-buckets with >50 txns: "
          f"{100*(per_hour > 50).mean():.1f}%\n")

    # ---- R3: time gap between consecutive same-card txns -------------------
    d = df.copy()
    d["prev_ts"] = d.groupby("card_id")["event_ts"].shift(1)
    d["prev_state"] = d.groupby("card_id")["merchant_state"].shift(1)
    d["gap_min"] = (d["event_ts"] - d["prev_ts"]).dt.total_seconds() / 60.0
    state_changes = d[(d["prev_state"].notna())
                      & (d["merchant_state"] != d["prev_state"])]
    print("=== Time gap (minutes) when a card CHANGES STATE (for R3 geo) ===")
    print(state_changes["gap_min"].describe(
        percentiles=[0.1, 0.25, 0.5]).to_string())
    print(f"  state-change events: {len(state_changes):,} "
          f"({100*len(state_changes)/len(df):.1f}% of all txns)")
    for thr in (5, 10, 15, 30):
        share = 100 * (state_changes["gap_min"] <= thr).mean()
        print(f"  state changes within {thr:>2} min: {share:.1f}%")
    print()

    # ---- Amount: fraud vs legit -------------------------------------------
    print("=== Amount distribution: legit vs fraud ===")
    print(df.groupby("is_fraud")["amount"].describe(
        percentiles=[0.5, 0.9, 0.99]).to_string())


if __name__ == "__main__":
    main()
