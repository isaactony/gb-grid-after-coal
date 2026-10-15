-- Grain: one row per settlement day. How complete is each source vs the expected number of
-- settlement periods (46/48/50)? Feeds the Data quality dashboard and a warn-level test.

with expected as (
    select settlement_date, count(*) as expected_periods
    from {{ ref('int_half_hours') }}
    group by 1
),

generation as (
    select settlement_date, count(distinct settlement_period) as periods, count(*) as fuel_rows
    from {{ ref('stg_elexon__generation_by_fuel') }}
    group by 1
),

demand as (
    select settlement_date, count(*) as periods
    from {{ ref('stg_elexon__demand_outturn') }}
    group by 1
),

price as (
    select
        settlement_date,
        count(*) filter (where data_provider = 'APXMIDP' and not is_zero_volume) as usable_periods,
        count(*) filter (where is_zero_volume)                                    as zero_volume_rows
    from {{ ref('stg_elexon__market_index') }}
    group by 1
),

grid as (
    select
        settlement_date,
        count(forecast_gco2_per_kwh)                                    as national_intensity_periods,
        count(actual_gco2_per_kwh)                                      as national_actual_periods,
        avg(abs(forecast_gco2_per_kwh - actual_gco2_per_kwh))           as intensity_forecast_mae
    from {{ ref('fct_grid_half_hourly') }}
    group by 1
),

regional as (
    select settlement_date, count(*) as region_periods
    from {{ ref('fct_regional_carbon_intensity') }}
    group by 1
)

select
    e.settlement_date,
    e.expected_periods,
    coalesce(g.periods, 0)                                          as generation_periods,
    coalesce(g.fuel_rows, 0)                                        as generation_fuel_rows,
    coalesce(d.periods, 0)                                          as demand_periods,
    coalesce(p.usable_periods, 0)                                   as price_periods,
    coalesce(p.zero_volume_rows, 0)                                 as price_zero_volume_rows_excluded,
    coalesce(gr.national_intensity_periods, 0)                      as national_intensity_periods,
    coalesce(re.region_periods, 0)                                  as regional_intensity_rows,
    round(gr.intensity_forecast_mae, 1)                             as intensity_forecast_mae,
    round(100.0 * coalesce(g.periods, 0) / e.expected_periods, 1)   as generation_completeness_pct,
    round(100.0 * coalesce(d.periods, 0) / e.expected_periods, 1)   as demand_completeness_pct,
    round(100.0 * coalesce(p.usable_periods, 0) / e.expected_periods, 1) as price_completeness_pct,
    round(100.0 * coalesce(gr.national_intensity_periods, 0) / e.expected_periods, 1) as national_intensity_completeness_pct,
    round(100.0 * coalesce(re.region_periods, 0) / (e.expected_periods * 18), 1)       as regional_completeness_pct,
    e.expected_periods in (46, 50)                                  as is_clock_change_day
from expected as e
left join generation as g using (settlement_date)
left join demand as d using (settlement_date)
left join price as p using (settlement_date)
left join grid as gr using (settlement_date)
left join regional as re using (settlement_date)
