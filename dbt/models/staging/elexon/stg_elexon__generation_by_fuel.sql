{{ config(
    materialized='incremental',
    unique_key=['settlement_date', 'settlement_period', 'fuel_type_code'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['half_hour_start_utc']}, {'columns': ['settlement_date', 'settlement_period']}],
) }}

-- Elexon FUELHH: average MW per fuel type per half-hour settlement period.
-- Only covers plant metered on the transmission network (no rooftop/embedded solar).
-- The same period can arrive in several responses (overlapping windows, re-fetches,
-- re-publications); keep the most recently published value.

with records as (
    {{ raw_records('elexon_fuelhh') }}
),

typed as (
    select
        (rec ->> 'startTime')::timestamptz      as half_hour_start_utc,
        (rec ->> 'settlementDate')::date        as settlement_date_as_published,
        (rec ->> 'settlementPeriod')::int       as settlement_period_as_published,
        -- Elexon published ElecLink as 'INTELE' instead of 'INTELEC' on 2021-09-10.
        case rec ->> 'fuelType' when 'INTELE' then 'INTELEC' else rec ->> 'fuelType' end
                                                as fuel_type_code,
        rec ->> 'fuelType'                      as fuel_type_code_as_published,
        (rec ->> 'generation')::numeric         as generation_mw,
        (rec ->> 'publishTime')::timestamptz    as published_at,
        fetched_at,
        response_id                             as source_response_id
    from records
    where (rec ->> 'startTime')::timestamptz >= ('{{ var("start_date") }}'::timestamp at time zone 'Europe/London')
),

ranked as (
    select
        *,
        {{ settlement_date_from_utc('half_hour_start_utc') }}   as settlement_date,
        {{ settlement_period_from_utc('half_hour_start_utc') }} as settlement_period,
        row_number() over (
            partition by half_hour_start_utc, fuel_type_code
            order by published_at desc, fetched_at desc
        ) as version_rank
    from typed
)

select
    half_hour_start_utc,
    settlement_date,
    settlement_period,
    settlement_date_as_published,
    settlement_period_as_published,
    fuel_type_code,
    fuel_type_code_as_published,
    generation_mw,
    published_at,
    source_response_id
from ranked
where version_rank = 1
