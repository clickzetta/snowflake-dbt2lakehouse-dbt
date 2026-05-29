{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_key',
    tags=['gold', 'run'],
    alias='DIM_ORDERS'
) }}

-- Migration note:
--   Source changed from stg_tpc_h__orders (full SF100, 1B+ rows) to stg_orders_incremental
--   to keep build time reasonable. stg_orders_incremental uses prune_days var (default 2 days).
--   dim_customers dedup added: qualify row_number() to avoid fan-out on join.

with orders_base as (
    select * from {{ ref('stg_orders_incremental') }}
),

customers as (
    select customer_key, customer_name, nation_key
    from {{ ref('dim_customers') }}
    qualify row_number() over (partition by customer_key order by dbt_updated_ts desc) = 1
),

enriched_orders as (
    select
        o.o_orderkey                                    as order_key,
        o.o_custkey                                     as customer_key,
        o.o_orderstatus                                 as order_status,
        o.o_totalprice                                  as total_price,
        o.o_orderdate                                   as order_date,
        o.o_orderpriority                               as order_priority,
        o.o_clerk                                       as clerk,
        o.o_shippriority                                as ship_priority,
        o.o_comment                                     as order_comment,
        c.customer_name,
        c.nation_key,
        o.order_status_desc,
        o.order_year,
        o.order_quarter,
        o.order_month,
        o.processed_at                                  as _loaded_at,
        current_timestamp()                             as _updated_at
    from orders_base o
    left join customers c on o.o_custkey = c.customer_key
)

select * from enriched_orders

{% if is_incremental() %}
where _loaded_at > (select max(_loaded_at) from {{ this }})
{% endif %}
