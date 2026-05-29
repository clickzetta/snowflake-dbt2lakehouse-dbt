-- cleanup.sql
-- Drops all objects created by 03_lakehouse dbt build.
-- Run after e2e validation or when resetting the test environment.
--
-- Usage:
--   cz-cli sql "$(cat cleanup.sql)" --profile aliyun_shanghai_prod --write

-- Bronze
DROP TABLE IF EXISTS dbt_migration_test_bronze.stg_tpc_h__customers;
DROP TABLE IF EXISTS dbt_migration_test_bronze.stg_tpc_h__orders;
DROP TABLE IF EXISTS dbt_migration_test_bronze.stg_tpc_h__nations;
DROP TABLE IF EXISTS dbt_migration_test_bronze.stg_tpc_h__regions;
DROP TABLE IF EXISTS dbt_migration_test_bronze.stg_orders_incremental;
DROP TABLE IF EXISTS dbt_migration_test_bronze.customer_cdc_stream;
DROP TABLE STREAM IF EXISTS dbt_migration_test_bronze.customer_cdc_stream_ts;

-- Silver
DROP TABLE IF EXISTS dbt_migration_test_silver.customer_segments;
DROP TABLE IF EXISTS dbt_migration_test_silver.LKP_EXCHANGE_RATES;
DROP TABLE IF EXISTS dbt_migration_test_silver.order_facts_dynamic;
DROP TABLE IF EXISTS dbt_migration_test_silver.customer_clustering;

-- Gold
DROP TABLE IF EXISTS dbt_migration_test_gold.dim_customers;
DROP TABLE STREAM IF EXISTS dbt_migration_test_gold.dim_customers_ts;
DROP TABLE IF EXISTS dbt_migration_test_gold.DIM_CUSTOMER_CHANGES;
DROP TABLE IF EXISTS dbt_migration_test_gold.DIM_ORDERS;
DROP TABLE IF EXISTS dbt_migration_test_gold.dim_current_year_orders;
DROP TABLE IF EXISTS dbt_migration_test_gold.dim_calendar_day;
DROP TABLE IF EXISTS dbt_migration_test_gold.customer_insights;

-- Raw (seeds)
DROP TABLE IF EXISTS dbt_migration_test_raw.fx_rates_timeseries;

-- Schemas
DROP SCHEMA IF EXISTS dbt_migration_test_bronze;
DROP SCHEMA IF EXISTS dbt_migration_test_silver;
DROP SCHEMA IF EXISTS dbt_migration_test_gold;
DROP SCHEMA IF EXISTS dbt_migration_test_raw;
DROP SCHEMA IF EXISTS dbt_migration_test;
