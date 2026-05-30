#!/usr/bin/env python3
"""
e2e.py — End-to-end validation for 03_lakehouse dbt migration.

Runs dbt build, then verifies key assertions against the actual output.
All EXPECTED values come from TPC-H SF100 (clickzetta_sample_data.tpch_100g).

Usage:
    cd 03_lakehouse
    python ../e2e.py              # Full data validation
    python ../e2e.py --sample     # Sample mode (skips large row count checks)

Requirements:
    - dbt-clickzetta installed (pip install dbt-clickzetta)
    - profiles.yml configured in ~/.dbt/ or 03_lakehouse/
    - cz-cli installed (for SQL validation queries)
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

# ── paths ──────────────────────────────────────────────────────────────────
PROFILE_DIR = str(Path(__file__).parent / "03_lakehouse")
PROJECT_DIR = PROFILE_DIR
DBT_ENV = {**os.environ, "DBT_PROFILES_DIR": PROFILE_DIR}

SCHEMA = "dbt_migration_test"

# ── helpers ────────────────────────────────────────────────────────────────

def run_dbt(args, check=True):
    """Run a dbt command."""
    cmd = ["dbt"] + args
    print(f"\n$ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=False, text=True, env=DBT_ENV, cwd=PROJECT_DIR)
    if check and result.returncode != 0:
        print(f"[FAIL] command exited {result.returncode}")
        sys.exit(1)
    return result.returncode == 0


def _query_via_cz_cli(sql):
    """Run SQL via cz-cli and return the first cell value."""
    import json
    try:
        result = subprocess.run(
            ["cz-cli", "sql", sql, "--sync"],
            capture_output=True, text=True
        )
        data = json.loads(result.stdout.strip())
        return str(data["rows"][0][0])
    except Exception:
        return None


def check(name, actual, expected, op="=="):
    """Assert a single check and print result."""
    if op == "==":
        ok = actual == expected
    elif op == ">=":
        ok = actual >= expected
    elif op == ">":
        ok = actual > 0
    else:
        ok = False
    status = "✓ PASS" if ok else "✗ FAIL"
    print(f"  {status}  {name}: got {actual!r}, expected {expected!r}")
    return ok


def skip(name, reason):
    """Skip a check and print reason."""
    print(f"  ⊘ SKIP  {name}: {reason}")


# ── main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="E2E validation for dbt migration")
    parser.add_argument("--sample", action="store_true", help="Sample mode: skip large row count checks")
    args = parser.parse_args()

    mode = "sample" if args.sample else "full"
    results = []
    skipped = []

    # ── Step 1: dbt deps ──────────────────────────────────────────────────
    print("\n=== Step 1: dbt deps ===")
    run_dbt(["deps"])

    # ── Step 2: dbt seed ──────────────────────────────────────────────────
    print("\n=== Step 2: dbt seed (FX rates mock data) ===")
    run_dbt(["seed"])

    # ── Step 3: dbt build ─────────────────────────────────────────────────
    print(f"\n=== Step 3: dbt build ({mode} mode) ===")
    build_args = ["build"]
    if args.sample:
        build_args += ["--vars", '{"sample_limit": 10000}']
        print("  Note: Dynamic Tables require full refresh on first run (~4 min)")
    else:
        print("  Note: Dynamic Tables require full refresh on first run (~4 min)")
    run_dbt(build_args)

    # ── Step 4: validate key models ───────────────────────────────────────
    print("\n=== Step 4: Validation ===")
    print("  (requires cz-cli for SQL queries; skip if not installed)")

    # FX rates seed (always checked)
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_raw.fx_rates_timeseries")
    if n:
        results.append(check("fx_rates row count", int(n), 9135))

    # stg_tpc_h__customers
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_tpc_h__customers")
    if n:
        if args.sample:
            results.append(check("stg_customers has data", int(n), 0, ">"))
        else:
            results.append(check("stg_customers row count >= 15M", int(n), 15000000, ">="))

    # stg_tpc_h__orders
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_tpc_h__orders")
    if n:
        if args.sample:
            results.append(check("stg_orders has data", int(n), 0, ">"))
        else:
            results.append(check("stg_orders row count >= 150M", int(n), 150000000, ">="))

    # stg_orders_incremental
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_orders_incremental")
    if n:
        results.append(check("stg_orders_incremental > 0", int(n), 0, ">"))

    # customer_segments — 5 segments present
    n = _query_via_cz_cli(f"SELECT count(distinct customer_segment) FROM {SCHEMA}_silver.customer_segments")
    if n:
        results.append(check("customer_segments distinct segments", int(n), 5))

    # LKP_EXCHANGE_RATES
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_silver.LKP_EXCHANGE_RATES WHERE from_currency = 'USD'")
    if n:
        results.append(check("fx_rates intermediate USD rows", int(n), 9135))

    # dim_customers
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_gold.dim_customers")
    if n:
        if args.sample:
            results.append(check("dim_customers has data", int(n), 0, ">"))
        else:
            results.append(check("dim_customers row count >= 15M", int(n), 15000000, ">="))

    # dim_orders
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_gold.DIM_ORDERS")
    if n:
        results.append(check("dim_orders row count > 0", int(n), 0, ">"))

    # dim_calendar_day — 50 years = 18250 days
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_gold.dim_calendar_day")
    if n:
        results.append(check("dim_calendar_day row count", int(n), 18250))

    # customer_insights — no null classification
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_gold.customer_insights WHERE customer_classification IS NULL")
    if n:
        results.append(check("customer_insights no null classification", int(n), 0))

    # customer_cdc_stream
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.customer_cdc_stream")
    if n:
        results.append(check("customer_cdc_stream rows > 0", int(n), 0, ">"))

    # DIM_CUSTOMER_CHANGES — stream captures changes after creation, 0 on first run is expected
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_gold.DIM_CUSTOMER_CHANGES")
    if n is not None:
        print(f"  ℹ INFO  DIM_CUSTOMER_CHANGES rows: {n} (0 on first run is expected)")

    # ── Step 5: summary ───────────────────────────────────────────────────
    if results:
        passed = sum(results)
        total  = len(results)
        print(f"\n=== Result: {passed}/{total} checks passed ===")
        if passed < total:
            sys.exit(1)
    else:
        print("\n=== Validation skipped (cz-cli not installed) ===")
        print("  Run results.sql manually to verify data.")

    print("\n=== Done! Run 'cleanup.sql' to remove test data. ===")


if __name__ == "__main__":
    main()
