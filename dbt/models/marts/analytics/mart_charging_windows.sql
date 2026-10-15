-- When is the cleanest time to plug in, by region? Average forecast intensity by local hour,
-- per region and month, ranked so rank 1 is the cleanest hour of the day.

with hourly as (
    select
        f.region_id,
        date_trunc('month', f.settlement_date)::date    as month_start,
        f.local_hour,
        avg(f.forecast_gco2_per_kwh)                    as avg_gco2_per_kwh,
        count(*)                                        as half_hours
    from {{ ref('fct_regional_carbon_intensity') }} as f
    group by 1, 2, 3
)

select
    h.region_id,
    r.region_name,
    r.region_type,
    h.month_start,
    h.local_hour,
    round(h.avg_gco2_per_kwh, 1)                                                    as avg_gco2_per_kwh,
    h.half_hours,
    rank() over (partition by h.region_id, h.month_start order by h.avg_gco2_per_kwh)       as cleanest_rank,
    round(h.avg_gco2_per_kwh / nullif(avg(h.avg_gco2_per_kwh) over (partition by h.region_id, h.month_start), 0), 3)
                                                                                    as vs_daily_average
from hourly as h
join {{ ref('dim_region') }} as r using (region_id)
