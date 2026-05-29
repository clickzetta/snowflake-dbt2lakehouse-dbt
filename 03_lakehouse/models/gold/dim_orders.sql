{{ config(
    materialized='incremental',
    unique_key='order_key',
    tags=['gold', 'run'],
    alias='DIM_ORDERS'
) }}

with orders_base as (
    select * from {{ ref('stg_tpc_h__orders') }}
),

customers as (
    select customer_key, customer_name, nation_key
    from {{ ref('dim_customers') }}
),

enriched_orders as (
    select
        o.order_key,
        o.customer_key,
        o.order_status,
        o.total_price,
        o.order_date,
        o.order_priority,
        o.clerk,
        o.ship_priority,
        o.order_comment,
        c.customer_name,
        c.nation_key,
        case
            when o.order_status = 'O' then 'Open'
            when o.order_status = 'F' then 'Fulfilled'
            when o.order_status = 'P' then 'Partial'
            else 'Unknown'
        end as order_status_desc,
        extract(year    from o.order_date) as order_year,
        extract(quarter from o.order_date) as order_quarter,
        extract(month   from o.order_date) as order_month,
        o._loaded_at,
        current_timestamp() as _updated_at
    from orders_base o
    left join customers c using (customer_key)
)

select * from enriched_orders

{% if is_incremental() %}
where _loaded_at > (select max(_loaded_at) from {{ this }})
{% endif %}
