-- Migration notes:
--   Snowflake: get_stream(ref('dim_customers')) macro → SHOW STREAMS / CREATE STREAM ... SHOW_INITIAL_ROWS
--              metadata$action, metadata$isupdate → Snowflake stream metadata columns
--              sequence_get_nextval() → Snowflake SEQUENCE .nextval
--              qualify ... row_number() → standard SQL, compatible
--   ClickZetta: get_table_stream(ref('dim_customers')) → CREATE TABLE STREAM ... TABLE_STREAM_MODE=ALL
--               __change_type replaces metadata$action
--               __commit_timestamp replaces metadata$isupdate
--               row_number() over (...) replaces sequence surrogate key

{{ config(
    materialized='incremental',
    alias='DIM_CUSTOMER_CHANGES'
) }}

select
    row_number() over (order by __commit_timestamp, customer_key) as log_id,
    d.*,
    case when __change_type = 'DELETE' then 'Y' else 'N' end as delete_flag
from {{ get_table_stream(ref('dim_customers')) }} as d
where not (__change_type = 'DELETE' and __change_type != 'UPDATE_BEFORE')
qualify 1 = row_number() over (
    partition by customer_key
    order by _updated_at desc, __change_type desc
)
