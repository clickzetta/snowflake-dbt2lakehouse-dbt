{{ config(
    materialized='table',
    tags=['gold', 'walk', 'analytics']
) }}

with customer_base as (
    select
        cs.*,
        cn.n_name    as nation_name
    from {{ ref('customer_segments') }} cs
    left join {{ source('TPC_H', 'NATION') }} cn on cs.nation_key = cn.n_nationkey
)

select
    customer_key,
    customer_name,
    nation_name                                  as country,
    account_balance,
    avg_nation_balance                           as country_average_balance,
    balance_vs_nation_avg                        as balance_vs_country_average,
    customer_segment                             as customer_tier,
    market_segment,
    nation_ranking                               as country_ranking,
    statistical_class                            as statistical_classification,
    round(balance_percentile * 100, 1)           as balance_percentile_score,
    balance_rank_in_nation                       as rank_in_country,
    case
        when customer_segment = 'PREMIUM' and nation_ranking = 'TOP_10_IN_NATION' then 'VIP Customer'
        when customer_segment in ('PREMIUM', 'HIGH_VALUE')                        then 'High Value Customer'
        when statistical_class = 'ABOVE_AVERAGE'                                  then 'Above Average Customer'
        else 'Standard Customer'
    end as customer_classification,
    case
        when account_balance < 0                then 'Credit Risk'
        when customer_segment = 'LOW_VALUE'     then 'Retention Risk'
        when balance_vs_nation_avg < -1000      then 'Performance Risk'
        else 'Low Risk'
    end as risk_category,
    processed_at as last_updated
from customer_base
order by account_balance desc
