{{ config(indexes=[{'columns': ['half_hour_start_utc'], 'unique': true}, {'columns': ['settlement_date']}]) }}

-- Grain: one row per half hour. The wide, analysis-ready table behind most dashboards:
-- generation by fuel group (Elexon), demand, wholesale price, national carbon intensity and
-- the Carbon Intensity mix (which includes embedded solar). Missing sources stay NULL.

{% set groups = dbt_utils.get_column_values(ref('fuel_types'), 'fuel_group', order_by='min(sort_order)') %}

select
    h.half_hour_start_utc,
    h.half_hour_start_local,
    h.settlement_date,
    h.settlement_period,
    h.local_hour,
    {% for grp in groups %}
    g.{{ grp | lower | replace(' ', '_') }}_mw,
    {% endfor %}
    g.domestic_generation_mw,
    g.total_supply_mw,
    round(100 * g.wind_mw / nullif(g.total_supply_mw, 0), 2)        as wind_share_of_supply_pct,
    round(100 * (g.gas_mw + g.coal_mw + g.other_fossil_mw)
              / nullif(g.total_supply_mw, 0), 2)                     as fossil_share_of_supply_pct,
    d.national_demand_mw,
    d.transmission_demand_mw,
    p.price_gbp_per_mwh,
    p.volume_mwh                                                     as traded_volume_mwh,
    ci.forecast_gco2_per_kwh,
    ci.actual_gco2_per_kwh,
    ci.intensity_band,
    mix.solar_pct                                                    as mix_solar_pct,
    mix.wind_pct                                                     as mix_wind_pct,
    mix.gas_pct                                                      as mix_gas_pct,
    mix.coal_pct                                                     as mix_coal_pct,
    mix.nuclear_pct                                                  as mix_nuclear_pct,
    mix.imports_pct                                                  as mix_imports_pct
from {{ ref('int_half_hours') }} as h
left join {{ ref('int_generation_pivoted') }} as g
       on g.settlement_date = h.settlement_date and g.settlement_period = h.settlement_period
left join {{ ref('stg_elexon__demand_outturn') }} as d
       on d.settlement_date = h.settlement_date and d.settlement_period = h.settlement_period
left join {{ ref('stg_elexon__market_index') }} as p
       on p.settlement_date = h.settlement_date
      and p.settlement_period = h.settlement_period
      and p.data_provider = 'APXMIDP'
      and not p.is_zero_volume
left join {{ ref('stg_carbon_intensity__national_intensity') }} as ci
       on ci.half_hour_start_utc = h.half_hour_start_utc
left join {{ ref('stg_carbon_intensity__national_generation_mix') }} as mix
       on mix.half_hour_start_utc = h.half_hour_start_utc
