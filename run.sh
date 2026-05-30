#!/bin/bash
# run.sh — One-click run for the dbt migration demo.
#
# Usage:
#   bash run.sh              # Sample 10K rows (~1 min, default)
#   bash run.sh --full       # Full data (1.5B orders, ~10 min)
#   bash run.sh --limit 50000 # Custom limit
#
# Prerequisites:
#   - Python 3.9+
#   - dbt-clickzetta installed (pip install dbt-clickzetta)
#   - profiles.yml configured (~/.dbt/profiles.yml or 03_lakehouse/profiles.yml)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/03_lakehouse"

cd "$PROJECT_DIR"

# Parse arguments
BUILD_ARGS=""
MODE="sample (10K rows, ~1 min)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            BUILD_ARGS="--vars '{\"sample_limit\": null}'"
            MODE="full (1.5B orders, ~10 min)"
            shift
            ;;
        --limit)
            BUILD_ARGS="--vars '{\"sample_limit\": $2}'"
            MODE="sample ($2 rows)"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash run.sh [--full | --limit <rows>]"
            exit 1
            ;;
    esac
done

echo "╔══════════════════════════════════════════════════════╗"
echo "║  dbt Snowflake → ClickZetta Migration Demo          ║"
echo "║  Mode: $MODE"
echo "╚══════════════════════════════════════════════════════╝"

echo ""
echo "=== 1/4 dbt deps ==="
dbt deps

echo ""
echo "=== 2/4 dbt seed (FX rates mock data) ==="
dbt seed

echo ""
if [ -n "$BUILD_ARGS" ]; then
    echo "=== 3/4 dbt build (full data, ~10 min) ==="
    echo "  Note: Dynamic Tables require full refresh on first run."
    echo "        This is normal — not stuck."
else
    echo "=== 3/4 dbt build (sample mode, ~1 min) ==="
fi
eval "dbt build $BUILD_ARGS"

echo ""
echo "=== 4/4 Done! ==="
echo ""
echo "Next steps:"
echo "  1. View results:    cz-cli sql \"\$(cat results.sql)\" --write"
echo "  2. Run tests:       dbt test"
echo "  3. Clean up:        cz-cli sql \"\$(cat cleanup.sql)\" --write"
