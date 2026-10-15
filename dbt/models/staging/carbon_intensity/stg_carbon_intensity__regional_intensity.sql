{{ config(
    materialized='incremental',
    unique_key=['half_hour_start_utc', 'region_id'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['region_id', 'half_hour_start_utc']}],
) }}

-- Regional forecast carbon intensity and generation mix per half hour.
-- Each record holds a nested `regions` array, which itself holds a `generationmix` array.

{% set fuels = ['biomass', 'coal', 'imports', 'gas', 'nuclear', 'other', 'hydro', 'solar', 'wind'] %}

with records as (
    {{ raw_records('carbon_regional') }}
),

regions as (
    select
        (rec ->> 'from')::timestamptz                   as half_hour_start_utc,
        (reg ->> 'regionid')::int                       as region_id,
        reg ->> 'shortname'                             as region_name,
        reg ->> 'dnoregion'                             as dno_region,
        (reg -> 'intensity' ->> 'forecast')::numeric    as forecast_gco2_per_kwh,
        reg -> 'intensity' ->> 'index'                  as intensity_band,
        (select jsonb_object_agg(m ->> 'fuel', (m ->> 'perc')::numeric)
           from jsonb_array_elements(reg -> 'generationmix') as m) as mix,
        fetched_at,
        response_id
    from records
    cross join lateral jsonb_array_elements(rec -> 'regions') as reg
)

select distinct on (half_hour_start_utc, region_id)
    half_hour_start_utc,
    region_id,
    region_name,
    dno_region,
    forecast_gco2_per_kwh,
    intensity_band,
    {% for f in fuels %}
    (mix ->> '{{ f }}')::numeric as {{ f }}_pct,
    {% endfor %}
    response_id as source_response_id
from regions
order by half_hour_start_utc, region_id, fetched_at desc
