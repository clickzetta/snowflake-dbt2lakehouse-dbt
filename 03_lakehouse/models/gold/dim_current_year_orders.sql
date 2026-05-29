{{ config(
    materialized='dynamic_table',
    refresh_vc='default',
    refresh_interval='1 hour',
    alias='DIM_CURRENT_YEAR_ORDERS',
    tags=['gold', 'crawl']
) }}

-- Migration note:
--   Snowflake: target_lag='DOWNSTREAM' (refresh triggered by downstream DT)
--   ClickZetta: DOWNSTREAM not supported — use explicit refresh_interval instead.
--               dateadd() is compatible.

select *
from {{ ref('dim_orders') }}
where order_date >= (
    select dateadd(year, -1, date_trunc('day', max(order_date)))
    from {{ ref('dim_orders') }}
)
order by order_key
