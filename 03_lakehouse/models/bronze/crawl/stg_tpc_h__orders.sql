{{ config(tags=['staging', 'tpc_h']) }}

with source as (
    select * from {{ source('TPC_H', 'ORDERS') }}
),

renamed as (
    select
        o_orderkey     as order_key,
        o_custkey      as customer_key,
        o_orderstatus  as order_status,
        o_totalprice   as total_price,
        o_orderdate    as order_date,
        o_orderpriority as order_priority,
        o_clerk        as clerk,
        o_shippriority as ship_priority,
        o_comment      as order_comment,
        current_timestamp() as _loaded_at
    from source
)

select * from renamed
