{{ config(tags=['staging', 'tpc_h']) }}

with source as (
    select * from {{ source('TPC_H', 'NATION') }}
),

renamed as (
    select
        n_nationkey as nation_key,
        n_name      as nation_name,
        n_regionkey as region_key,
        n_comment   as nation_comment,
        current_timestamp() as _loaded_at
    from source
)

select * from renamed
