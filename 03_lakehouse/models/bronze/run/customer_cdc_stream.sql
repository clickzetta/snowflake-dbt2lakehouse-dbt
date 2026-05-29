{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        pre_hook=[
            "{% if not is_incremental() %} drop table stream if exists {{ this.schema }}.{{ this.identifier }}_ts {% endif %}"
        ],
        post_hook=[
            "create table stream if not exists {{ this.schema }}.{{ this.identifier }}_ts on table {{ this.schema }}.{{ this.identifier }} with properties ('TABLE_STREAM_MODE' = 'STANDARD')"
        ]
    )
}}

-- Migration notes:
--   Snowflake: METADATA$ACTION / METADATA$ISUPDATE / METADATA$ROW_ID
--   ClickZetta: __change_type / __commit_timestamp / __commit_version are reserved names
--               → use cdc_change_type / cdc_commit_ts / cdc_version as aliases
--
--   sample (10) → TABLESAMPLE SYSTEM(10) (Snowflake sample syntax not supported)
--   TABLE_STREAM_MODE: 'ALL' not supported → use 'STANDARD' (captures INSERT/UPDATE/DELETE)
--   Snowflake post_hook: CREATE STREAM ... SHOW_INITIAL_ROWS = TRUE
--   ClickZetta post_hook: CREATE TABLE STREAM ... TABLE_STREAM_MODE = 'STANDARD'

select
    c_custkey                    as customer_key,
    c_name                       as customer_name,
    c_acctbal                    as account_balance,
    'INSERT'                     as cdc_change_type,
    current_timestamp()          as cdc_commit_ts,
    cast(c_custkey as varchar)   as cdc_version
from {{ source('TPC_H', 'CUSTOMER') }}

{% if is_incremental() %}
    TABLESAMPLE SYSTEM(10)
{% endif %}
