{{ config(severity='warn') }}

-- Flags complete days (after each source's start) where generation, demand or national
-- intensity coverage drops below 95%. Warn-level: gaps are real upstream outages, not bugs.

select settlement_date, generation_completeness_pct, demand_completeness_pct, national_intensity_completeness_pct
from {{ ref('mart_data_quality_daily') }}
where settlement_date < current_date - 1
  and (
       generation_completeness_pct < 95
    or demand_completeness_pct < 95
    or (settlement_date >= date '2017-09-27' and national_intensity_completeness_pct < 95)
  )
