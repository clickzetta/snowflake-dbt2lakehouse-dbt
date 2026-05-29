{{ config(tags=['staging', 'tpc_h']) }}

with source as (
    select * from {{ source('TPC_H', 'REGION') }}
),

renamed as (
    select
        r_regionkey as region_key,
        r_name      as region_name,
        r_comment   as region_comment,
        current_timestamp() as _loaded_at
    from source
)

select * from renamed
