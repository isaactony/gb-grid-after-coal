-- Grain: one row per half hour per Elexon fuel type.

select
    h.half_hour_start_utc,
    h.settlement_date,
    h.settlement_period,
    g.fuel_type_code,
    g.generation_mw,
    g.generation_mw / 2.0   as generation_mwh,
    g.published_at
from {{ ref('stg_elexon__generation_by_fuel') }} as g
join {{ ref('int_half_hours') }} as h using (settlement_date, settlement_period)
