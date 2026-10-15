-- How does wholesale price move with wind output? Half hours bucketed by wind share of supply.

select
    extract(year from settlement_date)::int                         as year,
    least(floor(wind_share_of_supply_pct / 10) * 10, 60)::int       as wind_share_band_start_pct,
    case when wind_share_of_supply_pct >= 60 then '60%+'
         else (least(floor(wind_share_of_supply_pct / 10) * 10, 60))::int || '–'
              || (least(floor(wind_share_of_supply_pct / 10) * 10, 60) + 10)::int || '%'
    end                                                             as wind_share_band,
    count(*)                                                        as half_hours,
    round(avg(price_gbp_per_mwh), 2)                                as avg_price_gbp_per_mwh,
    round(percentile_cont(0.5) within group (order by price_gbp_per_mwh)::numeric, 2) as median_price_gbp_per_mwh,
    round(avg(forecast_gco2_per_kwh), 1)                            as avg_gco2_per_kwh
from {{ ref('fct_grid_half_hourly') }}
where price_gbp_per_mwh is not null
  and wind_share_of_supply_pct is not null
group by 1, 2, 3
