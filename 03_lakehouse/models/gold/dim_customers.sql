{{ config(
    materialized='table',
    tags=['gold', 'walk']
) }}

-- Migration notes:
--   Snowflake: sequence_get_nextval() → row_number() over (...)
--              hash() → md5(concat(...))  (hash() not supported in ClickZetta)
--              transient=false, merge_exclude_columns, sysdate() → current_timestamp()

{%- set scd_surrogate_key  = "customer_surrogate_key" -%}
{%- set scd_integration_key = "integration_id" -%}
{%- set scd_cdc_hash_key   = "cdc_hash_key" -%}
{%- set scd_dbt_updated_at  = "dbt_updated_ts" -%}
{%- set scd_dbt_inserted_at = "dbt_inserted_ts" -%}

{{ config(
    materialized='incremental',
    unique_key=scd_integration_key
) }}

with source_data as (
    select
        c.customer_name,
        c.customer_address,
        c.nation_key,
        c.customer_phone,
        c.account_balance,
        c.market_segment,
        c.customer_comment,
        c.customer_key,
        coalesce(cast(c.customer_key as varchar), '') as {{ scd_integration_key }},
        md5(concat(
            coalesce(c.customer_name, ''), '|',
            coalesce(c.customer_address, ''), '|',
            coalesce(cast(c.nation_key as varchar), ''), '|',
            coalesce(c.customer_phone, ''), '|',
            coalesce(cast(c.account_balance as varchar), ''), '|',
            coalesce(c.market_segment, ''), '|',
            coalesce(c.customer_comment, '')
        )) as {{ scd_cdc_hash_key }},
        case when o.order_count > 0      then 'Y' else 'N' end as has_orders_flag,
        case when o.open_order_count > 0 then 'Y' else 'N' end as has_open_orders_flag,
        o.order_count,
        o.open_order_count
    from {{ ref('stg_tpc_h__customers') }} c
    left join {{ ref('int_customers__with_orders') }} o using (customer_key)
),

existing_data as (
    {% if is_incremental() %}
        select {{ scd_surrogate_key }}, {{ scd_integration_key }},
               {{ scd_cdc_hash_key }}, {{ scd_dbt_inserted_at }}
        from {{ this }}
    {% else %}
        select null as {{ scd_surrogate_key }},
               null as {{ scd_integration_key }},
               null as {{ scd_cdc_hash_key }},
               null as {{ scd_dbt_inserted_at }}
        limit 0
    {% endif %}
),

inserts as (
    select
        row_number() over (order by s.customer_key) as {{ scd_surrogate_key }},
        s.*,
        current_timestamp() as {{ scd_dbt_inserted_at }},
        current_timestamp() as {{ scd_dbt_updated_at }}
    from source_data s
    left join existing_data e on s.{{ scd_integration_key }} = e.{{ scd_integration_key }}
    where e.{{ scd_integration_key }} is null
),

updates as (
    select
        e.{{ scd_surrogate_key }},
        s.*,
        e.{{ scd_dbt_inserted_at }},
        current_timestamp() as {{ scd_dbt_updated_at }}
    from source_data s
    join existing_data e on s.{{ scd_integration_key }} = e.{{ scd_integration_key }}
    where s.{{ scd_cdc_hash_key }} != e.{{ scd_cdc_hash_key }}
)

select * from inserts
union all
select * from updates
