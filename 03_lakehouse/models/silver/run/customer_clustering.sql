{{
    config(
        materialized="table",
        tags=["silver", "run", "ml"]
    )
}}

-- SILVER RUN: Customer clustering (SQL approximation of Python KMeans).
--
-- Original Python model used scikit-learn KMeans which is not supported
-- by dbt-clickzetta (no Python submission method implemented).
-- This SQL version uses NTILE + rule-based scoring as a practical alternative.
--
-- Migration notes:
--   Snowflake: Python model via Snowpark stored procedure (sproc.register)
--   ClickZetta: Python models NOT supported — replaced with SQL approximation
--               using NTILE percentile binning and balance-based scoring.

with base as (
    select
        customer_key,
        customer_name,
        nation_key,
        account_balance,
        balance_percentile,
        balance_rank_in_nation,
        customer_segment,
        market_segment
    from {{ ref('customer_segments') }}
),

-- Use NTILE to create 5 clusters based on balance_percentile (proxy for KMeans)
clustered as (
    select
        *,
        ntile(5) over (order by balance_percentile desc) - 1 as ml_cluster
    from base
),

-- Compute cluster statistics for distance approximation
cluster_stats as (
    select
        ml_cluster,
        avg(account_balance) as center_balance,
        avg(balance_percentile) as center_percentile,
        stddev(account_balance) as stddev_balance
    from clustered
    group by ml_cluster
),

-- Assign cluster names and compute approximate distance
scored as (
    select
        c.customer_key,
        c.customer_name,
        c.nation_key,
        c.account_balance,
        c.balance_percentile,
        c.balance_rank_in_nation,
        c.customer_segment,
        c.market_segment,
        c.ml_cluster,
        cs.center_balance,
        cs.center_percentile,
        cs.stddev_balance,
        -- Approximate distance: standardized distance from cluster center
        abs(c.account_balance - cs.center_balance) / nullif(cs.stddev_balance, 0) as distance_to_cluster_center,
        case c.ml_cluster
            when 0 then 'Premium Elite'
            when 1 then 'High Value Stable'
            when 2 then 'Growth Potential'
            when 3 then 'Standard Base'
            when 4 then 'At Risk'
        end as cluster_name
    from clustered c
    join cluster_stats cs on c.ml_cluster = cs.ml_cluster
)

select
    customer_key,
    customer_name,
    nation_key,
    account_balance,
    balance_percentile,
    balance_rank_in_nation,
    customer_segment,
    market_segment,
    ml_cluster,
    cluster_name,
    round(distance_to_cluster_center, 4) as distance_to_cluster_center,
    case when distance_to_cluster_center > 2.0 then true else false end as is_cluster_outlier,
    round(1.0 - least(distance_to_cluster_center / nullif(max(distance_to_cluster_center) over (), 0), 1.0), 4) as ml_confidence_score,
    '1.0' as ml_model_version,
    'KMeans_NTILE_approx' as clustering_algorithm,
    5 as n_clusters_used,
    '["ACCOUNT_BALANCE", "BALANCE_PERCENTILE", "BALANCE_RANK_IN_NATION"]' as features_used
from scored
