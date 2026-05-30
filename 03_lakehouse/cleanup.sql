-- cleanup.sql
-- Drops all objects created by 03_lakehouse dbt build.
-- Run after e2e validation or when resetting the test environment.
--
-- Usage (any SQL client):
--   DROP SCHEMA dbt_migration_test_bronze CASCADE;
--   DROP SCHEMA dbt_migration_test_silver CASCADE;
--   DROP SCHEMA dbt_migration_test_gold CASCADE;
--   DROP SCHEMA dbt_migration_test_raw CASCADE;

DROP SCHEMA IF EXISTS dbt_migration_test_bronze CASCADE;
DROP SCHEMA IF EXISTS dbt_migration_test_silver CASCADE;
DROP SCHEMA IF EXISTS dbt_migration_test_gold CASCADE;
DROP SCHEMA IF EXISTS dbt_migration_test_raw CASCADE;
