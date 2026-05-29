#!/usr/bin/env python3
"""
e2e.py — End-to-end validation for 03_lakehouse dbt migration.

Runs dbt build, then verifies key assertions against the actual output.
All EXPECTED values come from TPC-H SF100 (clickzetta_sample_data.tpch_100g).

Usage:
    cd 03_lakehouse
    python ../e2e.py
"""

import os
import subprocess
import sys
from pathlib import Path

# ── connection (read from profiles.yml via env or direct) ──────────────────
PROFILE_DIR = str(Path(__file__).parent / "03_lakehouse")
PROJECT_DIR = PROFILE_DIR
DBT_BIN = str(Path(__file__).parent / ".venv/bin/dbt")
DBT_ENV = {**os.environ, "DBT_PROFILES_DIR": PROFILE_DIR}
DBT_CMD = [DBT_BIN]  # run with cwd=PROJECT_DIR

SCHEMA = "dbt_migration_test"

# ── helpers ────────────────────────────────────────────────────────────────

def run(cmd, check=True):
    print(f"\n$ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=False, text=True, env=DBT_ENV, cwd=PROJECT_DIR)
    if check and result.returncode != 0:
        print(f"[FAIL] command exited {result.returncode}")
        sys.exit(1)
    return result.returncode == 0


def cz_sql(sql, profile="aliyun_shanghai_prod"):
    """Run a SQL query via cz-cli and return the first cell value."""
    import json
    result = subprocess.run(
        ["cz-cli", "sql", sql, "--profile", profile, "--sync"],
        capture_output=True, text=True
    )
    data = json.loads(result.stdout.strip())
    return str(data["rows"][0][0])


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
    run(DBT_CMD + ["deps"])

    # ── Step 2: dbt seed ──────────────────────────────────────────────────
    print("\n=== Step 2: dbt seed (FX rates mock data) ===")
    run(DBT_CMD + ["seed"])

    # ── Step 3: dbt build (models + tests, exclude dynamic tables) ────────
    print("\n=== Step 3: dbt build (non-dynamic models) ===")
    run(DBT_CMD + ["build",
        "--exclude", "config.materialized:dynamic_table",
        "--exclude", "customer_clustering"])  # Python model needs ZettaPark env

    # ── Step 4: validate key models ───────────────────────────────────────
    print("\n=== Step 4: Validation ===")

    # FX rates seed
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_raw.fx_rates_timeseries")
    results.append(check("fx_rates row count", int(n), 9135))

    # stg_tpc_h__customers (deduped from SF100)
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_tpc_h__customers")
    results.append(check("stg_customers row count >= 15M", int(n), 15000000, ">="))

    # stg_tpc_h__orders
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_tpc_h__orders")
    results.append(check("stg_orders row count >= 150M", int(n), 150000000, ">="))

    # stg_orders_incremental
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_bronze.stg_orders_incremental")
    results.append(check("stg_orders_incremental > 0", int(n), 0, ">"))

    # customer_segments — 5 segments present
    n = cz_sql(f"SELECT count(distinct customer_segment) FROM {SCHEMA}_silver.customer_segments")
    results.append(check("customer_segments distinct segments", int(n), 5))

    # int_fx_rates__daily
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_silver.LKP_EXCHANGE_RATES WHERE from_currency = 'USD'")
    results.append(check("fx_rates intermediate USD rows", int(n), 9135))

    # dim_customers
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_gold.dim_customers")
    results.append(check("dim_customers row count >= 15M", int(n), 15000000, ">="))

    # dim_orders
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_gold.DIM_ORDERS")
    results.append(check("dim_orders row count > 0", int(n), 0, ">"))

    # dim_calendar_day — 50 years = 18250 days
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_gold.dim_calendar_day")
    results.append(check("dim_calendar_day row count", int(n), 18250))

    # customer_insights — no null classification
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_gold.customer_insights WHERE customer_classification IS NULL")
    results.append(check("customer_insights no null classification", int(n), 0))

    # customer_cdc_stream — rows loaded
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_bronze.customer_cdc_stream")
    results.append(check("customer_cdc_stream rows > 0", int(n), 0, ">"))

    # DIM_CUSTOMER_CHANGES — rows loaded
    n = cz_sql(f"SELECT count(*) FROM {SCHEMA}_gold.DIM_CUSTOMER_CHANGES")
    results.append(check("DIM_CUSTOMER_CHANGES rows > 0", int(n), 0, ">"))

    # ── Step 5: summary ───────────────────────────────────────────────────
    passed = sum(results)
    total  = len(results)
    print(f"\n=== Result: {passed}/{total} checks passed ===")

    if passed < total:
        sys.exit(1)


if __name__ == "__main__":
    main()
