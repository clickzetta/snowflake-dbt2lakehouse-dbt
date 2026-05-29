{{
    config(
        materialized='incremental',
        unique_key='customer_key',
        pre_hook=[
            "{% if not is_incremental() %} drop table stream if exists {{ this.database }}.{{ this.schema }}.{{ this.identifier }}_ts {% endif %}"
        ],
        post_hook=[
            "create table stream if not exists {{ this.database }}.{{ this.schema }}.{{ this.identifier }}_ts on table {{ this }} with properties ('TABLE_STREAM_MODE' = 'ALL')"
        ]
    )
}}

-- Migration note:
--   Snowflake: METADATA$ACTION / METADATA$ISUPDATE / METADATA$ROW_ID
--   ClickZetta: __change_type / __commit_timestamp / __commit_version
--
-- Snowflake post_hook: CREATE STREAM ... ON TABLE {{ this }} SHOW_INITIAL_ROWS = TRUE
-- ClickZetta post_hook: CREATE TABLE STREAM ... ON TABLE {{ this }} WITH PROPERTIES ('TABLE_STREAM_MODE' = 'ALL')

select
    c_custkey                    as customer_key,
    c_name                       as customer_name,
    c_acctbal                    as account_balance,
    'INSERT'                     as __change_type,
    current_timestamp()          as __commit_timestamp,
    cast(c_custkey as varchar)   as __commit_version
from {{ source('TPC_H', 'CUSTOMER') }}

{% if is_incremental() %}
    sample (10)
{% endif %}
