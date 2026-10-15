{{ config(severity='warn', warn_if='>1922') }}

-- Known upstream issue: Elexon's settlementDate label is one day late for the last period of the
-- day (48, or 46/50 on clock-change days) before 2022-07-15: 1,922 half hours.
-- We derive settlement date/period from startTime, so this is informational. The threshold
-- makes it warn only if the problem spreads beyond the known cases.

select distinct half_hour_start_utc, settlement_date, settlement_period,
       settlement_date_as_published, settlement_period_as_published
from {{ ref('stg_elexon__generation_by_fuel') }}
where (settlement_date, settlement_period) <> (settlement_date_as_published, settlement_period_as_published)
