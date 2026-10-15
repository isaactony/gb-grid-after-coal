-- Market Index Data: short-term wholesale price (£/MWh) and traded volume (MWh) per period.
-- Two providers report; N2EX has published zero volume throughout, so its zero price is
-- not a real price. Rows with zero volume are kept here and flagged; marts use APX only.

with records as (
    {{ raw_records('elexon_market_index') }}
),

typed as (
    select
        (rec ->> 'startTime')::timestamptz  as half_hour_start_utc,
        (rec ->> 'settlementDate')::date    as settlement_date_as_published,
        (rec ->> 'settlementPeriod')::int   as settlement_period_as_published,
        rec ->> 'dataProvider'              as data_provider,
        (rec ->> 'price')::numeric          as price_gbp_per_mwh,
        (rec ->> 'volume')::numeric         as volume_mwh,
        fetched_at
    from records
    where (rec ->> 'startTime')::timestamptz >= ('{{ var("start_date") }}'::timestamp at time zone 'Europe/London')
)

select distinct on (half_hour_start_utc, data_provider)
    half_hour_start_utc,
    {{ settlement_date_from_utc('half_hour_start_utc') }}   as settlement_date,
    {{ settlement_period_from_utc('half_hour_start_utc') }} as settlement_period,
    settlement_date_as_published,
    settlement_period_as_published,
    data_provider,
    price_gbp_per_mwh,
    volume_mwh,
    coalesce(volume_mwh, 0) = 0 as is_zero_volume
from typed
order by half_hour_start_utc, data_provider, fetched_at desc
