{{ config(severity='warn') }}

-- Britain's last coal plant (Ratcliffe-on-Soar) closed on 30 Sep 2024, yet FUELHH still reports
-- isolated COAL readings: one half hour at a time, always settlement period 21 (10:00–10:30) on a
-- Wednesday, every couple of months. Likely a metering/test artefact rather than real generation.
-- Kept as published (it is <0.01% of supply) and surfaced here so it's visible, not silently dropped.

select settlement_date, settlement_period, generation_mw
from {{ ref('stg_elexon__generation_by_fuel') }}
where fuel_type_code = 'COAL'
  and generation_mw > 0
  and settlement_date >= date '2024-10-01'
