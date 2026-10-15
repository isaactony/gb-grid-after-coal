-- Every Elexon half hour (all three datasets) must land on the spine with the same
-- settlement date and period. Catches any timezone or clock-change mistake.

with elexon as (
    select distinct half_hour_start_utc, settlement_date, settlement_period from {{ ref('stg_elexon__generation_by_fuel') }}
    union
    select half_hour_start_utc, settlement_date, settlement_period from {{ ref('stg_elexon__demand_outturn') }}
    union
    select half_hour_start_utc, settlement_date, settlement_period from {{ ref('stg_elexon__market_index') }}
)

select e.*
from elexon as e
left join {{ ref('int_half_hours') }} as h using (half_hour_start_utc)
where h.settlement_date is distinct from e.settlement_date
   or h.settlement_period is distinct from e.settlement_period
