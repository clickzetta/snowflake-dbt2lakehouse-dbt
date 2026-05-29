{{ config(
    materialized='table',
    tags=['gold', 'walk', 'reference']
) }}

-- Migration notes:
--   Snowflake: table(generator(rowcount => N)) for row generation
--              to_char(date, 'YYYYMMDD')::number(8,0) for date key
--              last_day(date, 'YEAR'/'WEEK') for period end dates
--   ClickZetta: recursive CTE not supported — use explode(sequence(0, N-1)) instead
--               cast(date_format(date, 'yyyyMMdd') as int) for date key
--               last_day() supports MONTH; YEAR/WEEK end dates computed manually

with date_series as (
    select
        date_add(date('1992-01-01'), pos) as day_dt,
        pos + 1                           as day_seq
    from (
        select explode(sequence(0, 50 * 365 - 1)) as pos
    ) t
),

calendar as (
    select
        day_seq,
        day_dt,
        cast(date_format(day_dt, 'yyyyMMdd') as int)      as day_key,
        date_format(day_dt, 'yyyy-MM-dd')                 as day_text,
        date_format(day_dt, 'dd.MM.yyyy')                 as day_eu_text,
        date_format(day_dt, 'dd')                         as day_of_month,
        extract(dayofweek from day_dt)                    as day_of_week_num,
        date_format(day_dt, 'EEEE')                       as day_of_week_name,
        extract(week    from day_dt)                      as week_of_year,
        extract(month   from day_dt)                      as month_num,
        date_format(day_dt, 'MMMM')                       as month_name,
        extract(quarter from day_dt)                      as quarter_num,
        extract(year    from day_dt)                      as year_num,
        date_trunc('year',  day_dt)                       as year_start_dt,
        date_trunc('month', day_dt)                       as month_start_dt,
        date_trunc('week',  day_dt)                       as week_start_dt,
        last_day(day_dt)                                  as month_end_dt,
        date(concat(extract(year from day_dt), '-12-31')) as year_end_dt,
        dateadd(day, 6, date_trunc('week', day_dt))       as week_end_dt,
        dateadd(year,  -1, day_dt)                        as year_ago_dt,
        dateadd(month, -1, day_dt)                        as month_ago_dt,
        dateadd(week,  -1, day_dt)                        as week_ago_dt,
        case when day_dt = current_date() then 'Y' else 'N' end as current_day_flag
    from date_series
)

select * from calendar
