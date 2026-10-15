-- A settlement day has 48 half-hour periods, except clock-change days: 46 on the last Sunday
-- of March (clocks go forward) and 50 on the last Sunday of October (clocks go back).
-- Checks the spine against that rule, computed independently of the timezone database.

with days as (
    select settlement_date, count(*) as periods
    from {{ ref('int_half_hours') }}
    where settlement_date < current_date  -- today is still in progress
    group by 1
),

expected as (
    select
        settlement_date,
        periods,
        case
            when extract(month from settlement_date) = 3 and extract(isodow from settlement_date) = 7
                 and settlement_date + 7 >= (date_trunc('month', settlement_date) + interval '1 month')::date then 46
            when extract(month from settlement_date) = 10 and extract(isodow from settlement_date) = 7
                 and settlement_date + 7 >= (date_trunc('month', settlement_date) + interval '1 month')::date then 50
            else 48
        end as expected_periods
    from days
)

select * from expected
where periods <> expected_periods
  and settlement_date > '{{ var("start_date") }}'
