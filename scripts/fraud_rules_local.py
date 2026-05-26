#!/usr/bin/env python3
"""
fraud_rules_local.py  (v2 — recalibrated, 3 rules)
==================================================
Prototype + validate fraud detection rules in pandas before porting to
PySpark for the Glue job.

CHANGELOG v1 -> v2
------------------
After analysing real data distributions (see analyze_distributions.py) we
found that v1 thresholds wildly over-flagged:
  - R2 velocity ">5/hour" fired on 69% of traffic (real median is 14/hour).
  - R3 geo "state change <60min" fired on 82% of traffic (changing state is
    NORMAL here, not a fraud signal).
We therefore:
  - DROPPED R3 entirely (not a discriminating signal in this dataset).
  - Recalibrated R2 to the observed p99 (~130/hour).
  - Strengthened R1 with an absolute amount threshold (legit p99 ~= $294,
    while frauds average ~$131 with a much fatter tail).

The 3 remaining rules (each adds a 0/1 flag)
--------------------------------------------
  R1 amount_anomaly : amount > (card mean + 3*std)  OR  amount > ABS_AMOUNT
  R2 velocity       : > VELOCITY_MAX_PER_HOUR txns for the card in that hour
  R4 odd_hour       : transaction in 00:00-05:00 AND amount in the top decile

Composite risk score
---------------------
  score = w1*R1 + w2*R2 + w4*R4
  risk_level: HIGH (>=3) / MEDIUM (>=1.5) / LOW (<1.5)

is_fraud is ground truth, used ONLY to evaluate the (unsupervised) rules.

Usage
-----
    python fraud_rules_local.py \
        --input "C:/Users/acelk/Desktop/projects/_datasets/prepared/transactions" \
        --save  "C:/Users/acelk/Desktop/projects/_datasets/scored_local.csv"
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

import pandas as pd

# ---- Tunable rule parameters, calibrated from analyze_distributions.py ----
ABS_AMOUNT_THRESHOLD = 300.0     # R1: absolute high-amount flag (~legit p99)
AMOUNT_STD_FACTOR = 3.0          # R1: per-card mean + factor*std
VELOCITY_MAX_PER_HOUR = 130      # R2: observed p99 of txns/card/hour
ODD_HOUR_START = 0               # R4: night window start (inclusive)
ODD_HOUR_END = 5                 # R4: night window end (exclusive)
ODD_HOUR_AMOUNT_QUANTILE = 0.90  # R4: "high amount" threshold

# Composite score weights (amount is the strongest signal in this dataset).
W_AMOUNT = 2.0
W_VELOCITY = 1.0
W_ODD_HOUR = 1.0


def load_data(input_dir: str) -> pd.DataFrame:
    files = glob.glob(os.path.join(input_dir, "**", "part.csv"), recursive=True)
    if not files:
        sys.exit(f"No part.csv found under {input_dir}")
    print(f"[load] reading {len(files)} partition file(s) ...")
    df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)
    df["event_ts"] = pd.to_datetime(
        df["year"].astype(str) + "-"
        + df["month"].astype(str).str.zfill(2) + "-"
        + df["day"].astype(str).str.zfill(2) + " "
        + df["time"].astype(str),
        format="%Y-%m-%d %H:%M", errors="coerce",
    )
    df = df.sort_values(["card_id", "event_ts"]).reset_index(drop=True)
    print(f"[load] {len(df):,} rows, {int(df['is_fraud'].sum())} real frauds")
    return df


def rule_amount_anomaly(df: pd.DataFrame) -> pd.Series:
    """R1: per-card statistical outlier OR absolute high amount."""
    stats = df.groupby("card_id")["amount"].agg(["mean", "std"]).fillna(0)
    stats["threshold"] = stats["mean"] + AMOUNT_STD_FACTOR * stats["std"]
    joined = df.merge(stats[["threshold"]], on="card_id", how="left")
    statistical = joined["amount"] > joined["threshold"]
    absolute = df["amount"] > ABS_AMOUNT_THRESHOLD
    return (statistical.values | absolute.values).astype(int)


def rule_velocity(df: pd.DataFrame) -> pd.Series:
    """R2: more than VELOCITY_MAX_PER_HOUR txns for a card within one hour."""
    tmp = df[["card_id", "event_ts"]].copy()
    tmp["hour_bucket"] = tmp["event_ts"].dt.floor("h")
    counts = (tmp.groupby(["card_id", "hour_bucket"]).size()
              .reset_index(name="txn_in_hour"))
    joined = tmp.merge(counts, on=["card_id", "hour_bucket"], how="left")
    return (joined["txn_in_hour"] > VELOCITY_MAX_PER_HOUR).astype(int).values


def rule_odd_hour(df: pd.DataFrame) -> pd.Series:
    """R4: night-time transaction with a high amount."""
    hour = df["event_ts"].dt.hour
    high_amount_threshold = df["amount"].quantile(ODD_HOUR_AMOUNT_QUANTILE)
    night = (hour >= ODD_HOUR_START) & (hour < ODD_HOUR_END)
    high = df["amount"] >= high_amount_threshold
    return (night & high).astype(int).values


def apply_rules(df: pd.DataFrame) -> pd.DataFrame:
    print("[rules] applying R1 amount anomaly ...")
    df["r1_amount_anomaly"] = rule_amount_anomaly(df)
    print("[rules] applying R2 velocity ...")
    df["r2_velocity"] = rule_velocity(df)
    print("[rules] applying R4 odd hour ...")
    df["r4_odd_hour"] = rule_odd_hour(df)

    df["risk_score"] = (
        W_AMOUNT * df["r1_amount_anomaly"]
        + W_VELOCITY * df["r2_velocity"]
        + W_ODD_HOUR * df["r4_odd_hour"]
    )

    def level(s: float) -> str:
        if s >= 3:
            return "HIGH"
        if s >= 1.5:
            return "MEDIUM"
        return "LOW"

    df["risk_level"] = df["risk_score"].apply(level)
    return df


def report(df: pd.DataFrame) -> None:
    print("\n==================== RULE FIRING COUNTS ====================")
    for col in ["r1_amount_anomaly", "r2_velocity", "r4_odd_hour"]:
        n = int(df[col].sum())
        print(f"  {col:<20}: {n:>6,} flagged ({100*n/len(df):.1f}% of traffic)")

    print("\n==================== RISK LEVEL DISTRIBUTION ===============")
    print(df["risk_level"].value_counts().to_string())

    print("\n==================== ALIGNMENT WITH REAL FRAUD =============")
    flagged = df[df["risk_score"] > 0]
    real_fraud = int(df["is_fraud"].sum())
    caught = int(flagged["is_fraud"].sum())
    if real_fraud:
        print(f"  Real frauds in data         : {real_fraud}")
        print(f"  Frauds flagged (score > 0)  : {caught}  "
              f"({100*caught/real_fraud:.1f}% recall)")
    print(f"  Total transactions flagged  : {len(flagged):,} "
          f"({100*len(flagged)/len(df):.1f}% of traffic)")
    if len(flagged):
        print(f"  Precision (flagged that are fraud): "
              f"{100*caught/len(flagged):.2f}%")

    print("\n  Risk level vs real fraud (counts):")
    print(pd.crosstab(df["risk_level"], df["is_fraud"]).to_string())

    # Per-rule precision: of the txns each rule flags, how many are fraud?
    print("\n  Per-rule precision (flagged that are real fraud):")
    for col in ["r1_amount_anomaly", "r2_velocity", "r4_odd_hour"]:
        sub = df[df[col] == 1]
        if len(sub):
            print(f"    {col:<20}: {100*sub['is_fraud'].mean():.2f}% "
                  f"({int(sub['is_fraud'].sum())}/{len(sub)})")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", required=True)
    ap.add_argument("--save", default=None)
    args = ap.parse_args()

    df = load_data(args.input)
    df = apply_rules(df)
    report(df)

    if args.save:
        df.to_csv(args.save, index=False)
        print(f"\n[save] scored dataset written to {args.save}")


if __name__ == "__main__":
    main()
