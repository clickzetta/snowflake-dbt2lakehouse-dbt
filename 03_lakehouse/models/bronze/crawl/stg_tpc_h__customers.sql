{{ config(tags=['staging', 'tpc_h']) }}

-- Note: clickzetta_sample_data.tpch_100g (SF100) contains duplicate customer_key values.
-- Dedup with row_number() keeping the first occurrence per customer_key.

with source as (
    select * from {{ source('TPC_H', 'CUSTOMER') }}
),

renamed as (
    select
        c_custkey    as customer_key,
        c_name       as customer_name,
        c_address    as customer_address,
        c_nationkey  as nation_key,
        c_phone      as customer_phone,
        c_acctbal    as account_balance,
        c_mktsegment as market_segment,
        c_comment    as customer_comment,
        current_timestamp() as _loaded_at
    from source
),

deduped as (
    select *,
        row_number() over (partition by customer_key order by customer_key) as rn
    from renamed
)

select
    customer_key, customer_name, customer_address, nation_key,
    customer_phone, account_balance, market_segment, customer_comment, _loaded_at
from deduped
where rn = 1
