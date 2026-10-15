-- National carbon intensity (gCO2/kWh) per half hour: day-ahead forecast and estimated actual.

with records as (
    {{ raw_records('carbon_national_intensity') }}
),

typed as (
    select
        (rec ->> 'from')::timestamptz                   as half_hour_start_utc,
        (rec -> 'intensity' ->> 'forecast')::numeric    as forecast_gco2_per_kwh,
        (rec -> 'intensity' ->> 'actual')::numeric      as actual_gco2_per_kwh,
        rec -> 'intensity' ->> 'index'                  as intensity_band,
        fetched_at
    from records
)

select distinct on (half_hour_start_utc)
    half_hour_start_utc,
    -- GB grid intensity has never exceeded ~600 g/kWh in this period; a run of ~2,800 forecasts
    -- in Dec 2018 is an upstream error. Null it out, keep the raw value for auditing.
    case when forecast_gco2_per_kwh <= 1000 then forecast_gco2_per_kwh end as forecast_gco2_per_kwh,
    forecast_gco2_per_kwh                                                   as forecast_gco2_per_kwh_as_published,
    forecast_gco2_per_kwh > 1000                                            as is_forecast_implausible,
    actual_gco2_per_kwh,
    intensity_band
from typed
order by half_hour_start_utc, fetched_at desc
