-- Migration notes:
--   Snowflake: get_stream(ref('dim_customers')) → SHOW STREAMS / CREATE STREAM ... SHOW_INITIAL_ROWS
--              metadata$action → Snowflake stream metadata column
--              sequence_get_nextval() → Snowflake SEQUENCE .nextval
--   ClickZetta: get_table_stream(ref('dim_customers')) → CREATE TABLE STREAM ... TABLE_STREAM_MODE=STANDARD
--               __change_type / __commit_timestamp / __commit_version are reserved names
--               → backtick-quote when referenced; avoid SELECT * which expands reserved columns
--               row_number() over (...) replaces sequence surrogate key

{{ config(
    materialized='incremental',
    alias='DIM_CUSTOMER_CHANGES'
) }}

select
    row_number() over (order by `__commit_timestamp`, customer_key) as log_id,
    customer_surrogate_key,
    customer_name,
    customer_address,
    nation_key,
    customer_phone,
    account_balance,
    market_segment,
    customer_comment,
    customer_key,
    integration_id,
    cdc_hash_key,
    has_orders_flag,
    has_open_orders_flag,
    order_count,
    open_order_count,
    dbt_inserted_ts,
    dbt_updated_ts,
    `__change_type`     as cdc_change_type,
    `__commit_timestamp` as cdc_commit_ts,
    `__commit_version`  as cdc_version,
    case when `__change_type` = 'DELETE' then 'Y' else 'N' end as delete_flag
from {{ get_table_stream(ref('dim_customers')) }} as d
where not (`__change_type` = 'DELETE' and `__change_type` != 'UPDATE_BEFORE')
qualify 1 = row_number() over (
    partition by customer_key
    order by `__commit_timestamp` desc, `__change_type` desc
)
