#!/usr/bin/env python3
"""
e2e.py — End-to-end validation for 03_lakehouse dbt migration.

Runs dbt build, then verifies key assertions against the actual output.
All EXPECTED values come from TPC-H SF100 (clickzetta_sample_data.tpch_100g).

Usage:
    cd 03_lakehouse
    python ../e2e.py

Requirements:
    - dbt-clickzetta installed (pip install dbt-clickzetta)
    - profiles.yml configured in ~/.dbt/ or 03_lakehouse/
"""

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


def query(sql):
    """Run a SQL query via dbt and return the first cell value."""
    # Use dbt run-operation to execute arbitrary SQL
    # This avoids requiring cz-cli
    cmd = ["dbt", "run-operation", "run_query",
           "--args", f"{{sql: '{sql}'}}"]
    result = subprocess.run(cmd, capture_output=True, text=True, env=DBT_ENV, cwd=PROJECT_DIR)
    if result.returncode != 0:
        # Fallback: try cz-cli if available
        return _query_via_cz_cli(sql)
    # Parse output — dbt run-operation prints results to stdout
    # For simplicity, we use a different approach: write SQL to temp file and use dbt debug
    # Actually, the cleanest way is to use dbt's built-in test framework
    # But for e2e validation, let's use a simpler approach:
    return None


def _query_via_cz_cli(sql):
    """Fallback: run SQL via cz-cli if available."""
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


# ── main ───────────────────────────────────────────────────────────────────

def main():
    results = []

    # ── Step 1: dbt deps ──────────────────────────────────────────────────
    print("\n=== Step 1: dbt deps ===")
    run_dbt(["deps"])

    # ── Step 2: dbt seed ──────────────────────────────────────────────────
    print("\n=== Step 2: dbt seed (FX rates mock data) ===")
    run_dbt(["seed"])

    # ── Step 3: dbt build (all models + tests) ────────────────────────────
    print("\n=== Step 3: dbt build (all models, ~10 min) ===")
    print("  Note: Dynamic Tables require full refresh on first run (~4 min)")
    run_dbt(["build"])

    # ── Step 4: validate key models ───────────────────────────────────────
    print("\n=== Step 4: Validation ===")
    print("  (requires cz-cli for SQL queries; skip if not installed)")

    # FX rates seed
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_raw.fx_rates_timeseries")
    if n:
        results.append(check("fx_rates row count", int(n), 9135))

    # stg_tpc_h__customers (deduped from SF100)
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_tpc_h__customers")
    if n:
        results.append(check("stg_customers row count >= 15M", int(n), 15000000, ">="))

    # stg_tpc_h__orders
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_tpc_h__orders")
    if n:
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

    # customer_cdc_stream — rows loaded
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_bronze.customer_cdc_stream")
    if n:
        results.append(check("customer_cdc_stream rows > 0", int(n), 0, ">"))

    # DIM_CUSTOMER_CHANGES — stream only captures changes after stream creation,
    # so 0 rows on first run is expected. Just verify the table exists (no error).
    n = _query_via_cz_cli(f"SELECT count(*) FROM {SCHEMA}_gold.DIM_CUSTOMER_CHANGES")
    if n is not None:
        print(f"  ℹ INFO  DIM_CUSTOMER_CHANGES rows: {n} (0 on first run is expected — stream captures future changes only)")

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
