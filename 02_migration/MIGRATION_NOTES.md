# Migration Notes: Snowflake → ClickZetta Lakehouse

## Data Sources

| Snowflake | ClickZetta | Notes |
|---|---|---|
| `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` | `clickzetta_sample_data.tpch_100g` | Built-in sample data, no import needed |
| Cybersyn Financial Economic Essentials (Marketplace) | `data/fx_rates_timeseries.csv` (seed) | Mock data covering 2020–2024, USD base, 5 currencies |

## profiles.yml

| Snowflake field | ClickZetta field |
|---|---|
| `type: snowflake` | `type: clickzetta` |
| `account` | `service` (e.g. `cn-shanghai-alicloud.api.clickzetta.com`) |
| `database` | `instance` |
| `warehouse` | `vcluster` |
| `role` | — (managed via workspace roles) |

## Changed Files in 03_lakehouse/

### models/bronze/_sources.yml
- `SNOWFLAKE_SAMPLE_DATA` / `TPCH_SF1` → `clickzetta_sample_data` / `tpch_100g`
- `ECONOMIC_ESSENTIALS` (Cybersyn) → `FX_RATES` (seed source)
- `SNOWFLAKE_TABLE_STREAM` → `CZ_TABLE_STREAM`

### models/bronze/run/customer_cdc_stream.sql
| Snowflake | ClickZetta |
|---|---|
| `METADATA$ACTION` | `cdc_change_type` (`__change_type` is a reserved name) |
| `METADATA$ISUPDATE` | `cdc_commit_ts` (`__commit_timestamp` is reserved) |
| `METADATA$ROW_ID` | `cdc_version` (`__commit_version` is reserved) |
| `post_hook: CREATE STREAM ... SHOW_INITIAL_ROWS = TRUE` | `post_hook: CREATE TABLE STREAM ... TABLE_STREAM_MODE = 'STANDARD'` |
| `TABLE_STREAM_MODE = 'ALL'` | Not supported — use `'STANDARD'` (INSERT/UPDATE/DELETE) or `'APPEND_ONLY'` |

### models/silver/run/order_facts_dynamic.sql
| Snowflake | ClickZetta |
|---|---|
| `snowflake_warehouse=target.warehouse` | `refresh_vc='default_ap'` |
| `target_lag='1 hour'` | `refresh_interval='1 hour'` |
| `on_configuration_change='apply'` | Not supported — use `ALTER DYNAMIC TABLE` |
| `extract(dayofweek from ...)` | `dayofweek(...)` function |

### models/silver/walk/customer_segments.sql
- Removed `indexes: [{type: 'hash'}]` — hash index not supported in ClickZetta
- Use bloomfilter index for equality lookups if needed

### models/silver/run/customer_clustering.py
| Snowflake | ClickZetta |
|---|---|
| `import snowflake.snowpark as snowpark` | Standard Python (ZettaPark session compatible) |
| `session.sproc.register(...)` | Not supported — removed parallel stored procedure logic |
| `packages=['snowflake-snowpark-python', 'joblib']` | `packages=['scikit-learn', 'pandas', 'numpy']` |

### models/gold/dim_customers.sql / dim_orders.sql
| Snowflake | ClickZetta |
|---|---|
| `sequence_get_nextval()` macro | `row_number() over (order by ...)` |
| `transient=false` | Removed (not supported) |
| `merge_exclude_columns=[...]` | Removed (not supported) |
| `sysdate()` | `current_timestamp()` |
| `null::timestamp_ntz` | `null` |

### models/gold/dim_customer_changes.sql
| Snowflake | ClickZetta |
|---|---|
| `get_stream(ref('dim_customers'))` macro | `get_table_stream(ref('dim_customers'))` macro |
| `metadata$action = 'DELETE'` | `__change_type = 'DELETE'` |
| `metadata$isupdate` | `__change_type = 'UPDATE_BEFORE'` |

### models/gold/dim_calendar_day.sql
| Snowflake | ClickZetta |
|---|---|
| `table(generator(rowcount => N))` | `explode(sequence(0, N-1))` |
| `to_char(date, 'YYYYMMDD')::number(8,0)` | `cast(date_format(date, 'yyyyMMdd') as int)` |
| `last_day(date, 'YEAR'/'WEEK')` | Computed manually (`date(concat(year, '-12-31'))`, `dateadd(day, 6, week_start)`) |

### models/gold/dim_current_year_orders.sql
| Snowflake | ClickZetta |
|---|---|
| `target_lag='DOWNSTREAM'` | `refresh_interval='1 hour'` (DOWNSTREAM not supported) |

### macros/get_table_stream.sql
- Replaces Snowflake's `get_stream()` macro
- Uses `CREATE TABLE STREAM ... WITH PROPERTIES ('TABLE_STREAM_MODE' = 'ALL')`

## Additional Findings from Live Validation

These issues were discovered during actual `dbt build` against ClickZetta (not visible from static code review):

| Issue | Snowflake behavior | ClickZetta behavior | Fix |
|---|---|---|---|
| `float8` type in seeds | Supported | **Fixed in dbt-clickzetta 1.6.2** — `float8` now maps to `double` automatically. Explicit `column_types` still recommended for performance (avoids type inference overhead). |
| `hash()` function | Built-in multi-column hash | Not supported | `hash_combine(crc32(col1), crc32(col2), ...)` — `hash_combine_commutative` requires bigint args, use `crc32()` to convert varchar first |
| `__change_type` as column alias | Allowed | Reserved name — error | Use `cdc_change_type` as alias; backtick-quote when reading from stream |
| `TABLE_STREAM_MODE = 'ALL'` | Not applicable | Not supported | Use `'STANDARD'` or `'APPEND_ONLY'` |
| `this.database` in macros | Returns database name | Returns `None` | Use `this.schema.identifier` form |
| `table(generator(rowcount=>N))` | Row generator | Not supported | Use `explode(sequence(0, N-1))` |
| Recursive CTE (`WITH RECURSIVE`) | Supported | Not supported | Use `explode(sequence(...))` |
| SF100 duplicate primary keys | CUSTOMER has unique C_CUSTKEY | tpch_100g SF100 has duplicate C_CUSTKEY | Add `qualify row_number() over (partition by customer_key ...) = 1` dedup |
| `merge_exclude_columns` config | Supported | Not supported | Remove from config |
| `transient=false` config | Supported | Not supported | Remove from config |
| `null::timestamp_ntz` | Snowflake type cast | Not supported | Use plain `null` |
| `sysdate()` | Current timestamp | Not supported | Use `current_timestamp()` |

| Feature | Files | Reason |
|---|---|---|
| Snowflake SEQUENCE objects | `macros/snowflake_sequences.sql` | No sequence DDL in ClickZetta; use `row_number()` |
| Secure views | `models/gold/walk/sensitive_data/` | ClickZetta uses workspace-level access control |
| `copy_grants` | `dbt_project.yml` | Not applicable |
| Dynamic warehouse assignment | `seeds/dynamic_warehouses.csv` | ClickZetta uses `vcluster` per-model config |
| `table(generator(...))` | `dim_calendar_day.sql` | Replaced with recursive CTE |
| Snowpark stored procedures | `async_bulk_operations.py` | Replaced with standard pandas processing |
