{{ config(
    materialized='table',
    tags=['intermediate', 'fx_rates'],
    alias='LKP_EXCHANGE_RATES'
) }}

-- Migration note:
--   Snowflake: source('ECONOMIC_ESSENTIALS', 'FX_RATES_TIMESERIES') from Cybersyn Marketplace
--   ClickZetta: source('FX_RATES', 'fx_rates_timeseries') from mock seed data in data/
--   dateadd() is compatible in ClickZetta.

with fx_rates_transformed as (
    select
        rate_date                                                as day_dt,
        base_currency                                           as from_currency,
        quote_currency                                          as to_currency,
        exchange_rate                                           as conversion_rate,
        case
            when lead(rate_date) over (
                partition by base_currency, quote_currency
                order by rate_date
            ) is not null
            then dateadd(day, -1, lead(rate_date) over (
                partition by base_currency, quote_currency
                order by rate_date
            ))
            else date('2099-12-31')
        end as end_date,
        current_timestamp() as _loaded_at
    from {{ source('FX_RATES', 'fx_rates_timeseries') }}
    where base_currency = 'USD'
)

select * from fx_rates_transformed
