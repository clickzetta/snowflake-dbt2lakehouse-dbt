# snowflake-dbt2lakehouse-dbt

Migrating a real-world Snowflake dbt project to ClickZetta Lakehouse.

**Source project**: [sfc-gh-dflippo/snowflake-dbt-demo](https://github.com/sfc-gh-dflippo/snowflake-dbt-demo)  
**Dataset**: TPC-H (built-in sample data on both platforms) + mock FX rates seed

## Repository Structure

```
01_snowflake/   Original Snowflake dbt project (unchanged)
02_migration/   Migration notes — what changed and why
03_lakehouse/   ClickZetta version (runnable with dbt-clickzetta)
```

## Key Migration Points

| Feature | Snowflake | ClickZetta |
|---|---|---|
| Dynamic Table config | `snowflake_warehouse` + `target_lag` | `refresh_vc` + `refresh_interval` |
| CDC stream columns | `METADATA$ACTION` | `__change_type` |
| Row generation | `table(generator(...))` | Recursive CTE |
| Surrogate key | `SEQUENCE .nextval` | `row_number() over (...)` |
| Python models | Snowpark (`sproc.register`) | ZettaPark (standard pandas) |
| Marketplace data | Cybersyn FX rates | Mock seed CSV |

See [02_migration/MIGRATION_NOTES.md](02_migration/MIGRATION_NOTES.md) for the full diff.

## Quick Start (ClickZetta)

```bash
cd 03_lakehouse
cp profiles.yml.example ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml with your connection details

pip install dbt-clickzetta
dbt deps
dbt seed          # Load mock FX rates
dbt build         # Run all models and tests
```

## Data Sources

- **TPC-H**: Available as `clickzetta_sample_data.tpch_100g` on ClickZetta (no import needed)
- **FX rates**: `data/fx_rates_timeseries.csv` — mock USD-based daily rates for EUR/CNY/JPY/GBP/CAD (2020–2024)
