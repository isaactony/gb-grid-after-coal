-- Initial demand outturn per settlement period, in MW.
--   INDO  = national demand (excludes station load, pumping and exports)
--   ITSDO = transmission system demand (includes them)

with records as (
    {{ raw_records('elexon_demand_outturn') }}
),

typed as (
    select
        (rec ->> 'startTime')::timestamptz                          as half_hour_start_utc,
        (rec ->> 'settlementDate')::date                            as settlement_date_as_published,
        (rec ->> 'settlementPeriod')::int                           as settlement_period_as_published,
        (rec ->> 'initialDemandOutturn')::numeric                   as national_demand_mw,
        (rec ->> 'initialTransmissionSystemDemandOutturn')::numeric as transmission_demand_mw,
        (rec ->> 'publishTime')::timestamptz                        as published_at,
        fetched_at
    from records
    where (rec ->> 'startTime')::timestamptz >= ('{{ var("start_date") }}'::timestamp at time zone 'Europe/London')
)

select distinct on (half_hour_start_utc)
    half_hour_start_utc,
    {{ settlement_date_from_utc('half_hour_start_utc') }}   as settlement_date,
    {{ settlement_period_from_utc('half_hour_start_utc') }} as settlement_period,
    settlement_date_as_published,
    settlement_period_as_published,
    national_demand_mw,
    transmission_demand_mw,
    published_at
from typed
order by half_hour_start_utc, published_at desc, fetched_at desc
