{{ config(indexes=[{'columns': ['region_id', 'half_hour_start_utc'], 'unique': true}]) }}

-- Grain: one row per half hour per Carbon Intensity region (forecast intensity + mix %).

select
    r.half_hour_start_utc,
    h.half_hour_start_local,
    h.settlement_date,
    h.local_hour,
    r.region_id,
    r.forecast_gco2_per_kwh,
    r.intensity_band,
    r.wind_pct,
    r.solar_pct,
    r.gas_pct,
    r.nuclear_pct,
    r.hydro_pct,
    r.imports_pct,
    r.biomass_pct,
    r.coal_pct
from {{ ref('stg_carbon_intensity__regional_intensity') }} as r
join {{ ref('int_half_hours') }} as h using (half_hour_start_utc)
