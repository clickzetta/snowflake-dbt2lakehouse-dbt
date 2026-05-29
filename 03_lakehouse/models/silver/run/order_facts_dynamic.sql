{{ config(
    materialized='dynamic_table',
    refresh_vc='default',
    refresh_interval='1 hour',
    tags=['silver', 'run', 'real_time']
) }}

-- Migration notes:
--   Snowflake: snowflake_warehouse=target.warehouse, target_lag='1 hour', on_configuration_change='apply'
--   ClickZetta: refresh_vc='default', refresh_interval='1 hour'
--               on_configuration_change not supported — use ALTER DYNAMIC TABLE to change config
--
--   extract(dayofweek ...) → ClickZetta uses dayofweek() function or extract(dow ...)
--   Both platforms support date_trunc, extract(year/month/quarter), stddev, count(distinct)

{% set order_statuses   = ['O', 'F', 'P'] %}
{% set priority_levels  = ['1-URGENT', '2-HIGH', '3-MEDIUM', '4-NOT SPECIFIED', '5-LOW'] %}

select
    date_trunc('day', o_orderdate)      as order_date,
    extract(year    from o_orderdate)   as order_year,
    extract(month   from o_orderdate)   as order_month,
    extract(quarter from o_orderdate)   as order_quarter,
    dayofweek(o_orderdate)              as day_of_week,

    o_custkey      as customer_key,
    o_orderstatus  as order_status,
    o_orderpriority as order_priority,

    count(*)                                          as order_count,
    sum(o_totalprice)                                 as total_order_value,
    avg(o_totalprice)                                 as avg_order_value,
    min(o_totalprice)                                 as min_order_value,
    max(o_totalprice)                                 as max_order_value,
    stddev(o_totalprice)                              as order_value_stddev,
    count(distinct o_custkey)                         as unique_customers,
    sum(o_totalprice) / count(distinct o_custkey)     as revenue_per_customer,

    {% for status in order_statuses %}
    sum(case when o_orderstatus = '{{ status }}' then o_totalprice else 0 end) as revenue_{{ status.lower() }}_status,
    count(case when o_orderstatus = '{{ status }}' then 1 end)                 as count_{{ status.lower() }}_status,
    {% endfor %}

    {% for priority in priority_levels %}
    sum(case when o_orderpriority = '{{ priority }}' then o_totalprice else 0 end) as revenue_priority_{{ loop.index }},
    {% endfor %}

    current_timestamp() as last_updated

from {{ ref('stg_orders_incremental') }}
where processing_type in ('RECENT', 'FULL_LOAD')
group by
    date_trunc('day', o_orderdate),
    extract(year    from o_orderdate),
    extract(month   from o_orderdate),
    extract(quarter from o_orderdate),
    dayofweek(o_orderdate),
    o_custkey,
    o_orderstatus,
    o_orderpriority
