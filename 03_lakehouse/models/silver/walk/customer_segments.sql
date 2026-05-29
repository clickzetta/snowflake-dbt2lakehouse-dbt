{{ config(
    materialized='table',
    tags=['silver', 'walk', 'business_logic']
) }}

-- Migration notes:
--   Snowflake: indexes type 'hash' not supported in ClickZetta — removed.
--   Source ref changed: stg_customers_with_tests → stg_tpc_h__customers
--   Column names use renamed versions from stg_tpc_h__customers:
--     c_custkey → customer_key, c_name → customer_name,
--     c_nationkey → nation_key, c_acctbal → account_balance,
--     c_mktsegment → market_segment

with customer_metrics as (
    select
        customer_key,
        customer_name,
        nation_key,
        account_balance,
        market_segment,
        row_number()   over (partition by nation_key order by account_balance desc) as balance_rank_in_nation,
        percent_rank() over (order by account_balance)                              as balance_percentile,
        avg(account_balance) over (partition by nation_key)                         as avg_nation_balance,
        stddev(account_balance) over (partition by nation_key)                      as stddev_nation_balance
    from {{ ref('stg_tpc_h__customers') }}
),

segmented_customers as (
    select
        *,
        case
            when balance_percentile >= 0.9 then 'PREMIUM'
            when balance_percentile >= 0.7 then 'HIGH_VALUE'
            when balance_percentile >= 0.3 then 'STANDARD'
            when balance_percentile >= 0.1 then 'BASIC'
            else 'LOW_VALUE'
        end as customer_segment,
        case
            when balance_rank_in_nation <= 10  then 'TOP_10_IN_NATION'
            when balance_rank_in_nation <= 100 then 'TOP_100_IN_NATION'
            else 'STANDARD_IN_NATION'
        end as nation_ranking,
        case
            when account_balance > (avg_nation_balance + stddev_nation_balance) then 'ABOVE_AVERAGE'
            when account_balance < (avg_nation_balance - stddev_nation_balance) then 'BELOW_AVERAGE'
            else 'AVERAGE'
        end as statistical_class
    from customer_metrics
)

select
    customer_key,
    customer_name,
    nation_key,
    account_balance,
    market_segment,
    customer_segment,
    nation_ranking,
    statistical_class,
    balance_percentile,
    balance_rank_in_nation,
    round(avg_nation_balance, 2)                     as avg_nation_balance,
    round(account_balance - avg_nation_balance, 2)   as balance_vs_nation_avg,
    current_timestamp()                              as processed_at
from segmented_customers
