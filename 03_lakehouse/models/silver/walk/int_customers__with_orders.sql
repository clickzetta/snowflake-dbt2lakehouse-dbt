{{ config(
    materialized='ephemeral',
    tags=['intermediate', 'customers'],
    alias='LKP_CUSTOMERS_WITH_ORDERS'
) }}

with customer_orders as (
    select
        customer_key,
        count(*) as order_count,
        sum(case when order_status = 'O' then 1 else 0 end) as open_order_count
    from {{ ref('stg_tpc_h__orders') }}
    group by customer_key
)

select * from customer_orders
