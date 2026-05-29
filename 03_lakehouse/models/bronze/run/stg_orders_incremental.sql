{{ config(
    materialized='incremental',
    unique_key='o_orderkey',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    tags=['bronze', 'run', 'incremental']
) }}

select
    o_orderkey,
    o_custkey,
    o_orderstatus,
    o_totalprice,
    o_orderdate,
    o_orderpriority,
    o_clerk,
    o_shippriority,
    o_comment,

    case
        when o_orderstatus = 'O' then 'OPEN'
        when o_orderstatus = 'F' then 'FULFILLED'
        when o_orderstatus = 'P' then 'PARTIAL'
        else 'UNKNOWN'
    end as order_status_desc,

    date_trunc('month', o_orderdate) as order_month,
    extract(year  from o_orderdate)  as order_year,
    extract(quarter from o_orderdate) as order_quarter,

    current_timestamp() as processed_at,

    {% if is_incremental() %}
        case
            when o_orderdate >= dateadd(day, -{{ var('prune_days') }}, current_date())
            then 'RECENT'
            else 'HISTORICAL'
        end as processing_type
    {% else %}
        'FULL_LOAD' as processing_type
    {% endif %}

from {{ source('TPC_H', 'ORDERS') }}

{% if is_incremental() %}
where o_orderdate >= dateadd(day, -{{ var('prune_days') }}, current_date())
   or o_orderkey > (select coalesce(max(o_orderkey), 0) from {{ this }})
{% endif %}
