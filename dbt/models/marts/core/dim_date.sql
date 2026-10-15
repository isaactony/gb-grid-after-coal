with dates as (
    select distinct settlement_date as date_day from {{ ref('int_half_hours') }}
)

select
    d.date_day,
    extract(year from d.date_day)::int                              as year,
    extract(quarter from d.date_day)::int                           as quarter,
    extract(month from d.date_day)::int                             as month,
    to_char(d.date_day, 'Mon')                                      as month_name,
    date_trunc('month', d.date_day)::date                           as month_start,
    date_trunc('week', d.date_day)::date                            as week_start,
    extract(isodow from d.date_day)::int                            as iso_day_of_week,
    to_char(d.date_day, 'Dy')                                       as day_name,
    extract(isodow from d.date_day) in (6, 7)                       as is_weekend,
    case
        when extract(month from d.date_day) in (12, 1, 2) then 'Winter'
        when extract(month from d.date_day) in (3, 4, 5)  then 'Spring'
        when extract(month from d.date_day) in (6, 7, 8)  then 'Summer'
        else 'Autumn'
    end                                                             as season,
    d.date_day >= date '2024-10-01'                                 as is_after_last_coal_plant,
    e.event
from dates as d
left join {{ ref('grid_events') }} as e on e.event_date = d.date_day
