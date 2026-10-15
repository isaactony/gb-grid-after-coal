-- Grain: one row per settlement day. Energy in GWh (sum of MW x 0.5h / 1000).

{% set groups = ['gas', 'coal', 'nuclear', 'wind', 'hydro', 'biomass', 'imports', 'storage', 'other_fossil', 'other'] %}

with daily as (
    select
        settlement_date,
        {% for g in groups %}
        sum({{ g }}_mw) / 2000.0                                    as {{ g }}_gwh,
        {% endfor %}
        sum(total_supply_mw) / 2000.0                               as total_supply_gwh,
        sum(national_demand_mw) / 2000.0                            as national_demand_gwh,
        avg(price_gbp_per_mwh)                                      as avg_price_gbp_per_mwh,
        min(price_gbp_per_mwh)                                      as min_price_gbp_per_mwh,
        max(price_gbp_per_mwh)                                      as max_price_gbp_per_mwh,
        count(*) filter (where price_gbp_per_mwh < 0)               as negative_price_periods,
        avg(coalesce(actual_gco2_per_kwh, forecast_gco2_per_kwh))   as avg_gco2_per_kwh,
        avg(mix_solar_pct)                                          as avg_mix_solar_pct,
        count(*) filter (where coal_mw > 0)                         as periods_with_coal
    from {{ ref('fct_grid_half_hourly') }}
    group by 1
)

select
    d.*,
    round(100 * wind_gwh / nullif(total_supply_gwh, 0), 2)                          as wind_share_pct,
    round(100 * coal_gwh / nullif(total_supply_gwh, 0), 2)                          as coal_share_pct,
    round(100 * gas_gwh / nullif(total_supply_gwh, 0), 2)                           as gas_share_pct,
    round(100 * nuclear_gwh / nullif(total_supply_gwh, 0), 2)                       as nuclear_share_pct,
    round(100 * imports_gwh / nullif(total_supply_gwh, 0), 2)                       as imports_share_pct,
    round(100 * (wind_gwh + nuclear_gwh + hydro_gwh + biomass_gwh)
              / nullif(total_supply_gwh, 0), 2)                                     as low_carbon_share_pct,
    periods_with_coal = 0                                                           as is_coal_free_day,
    dd.year,
    dd.month_start,
    dd.season,
    dd.is_weekend,
    dd.is_after_last_coal_plant,
    dd.event
from daily as d
join {{ ref('dim_date') }} as dd on dd.date_day = d.settlement_date
