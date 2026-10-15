{#
  GB settlement date and period for a UTC instant. Periods count elapsed half hours from
  local (Europe/London) midnight: 1–48 normally, 1–46 / 1–50 on clock-change days.

  Elexon's own settlementDate label is one day late for the last period of each day (48, or
  46/50 on clock-change days) before 2022-07-15; its startTime is correct (verified by comparing
  each period with its neighbours). So the Elexon staging models derive both from startTime.
#}
{% macro settlement_date_from_utc(ts) -%}
    (({{ ts }}) at time zone 'Europe/London')::date
{%- endmacro %}

{% macro settlement_period_from_utc(ts) -%}
    (1 + floor(extract(epoch from
        ({{ ts }}) - ((({{ ts }}) at time zone 'Europe/London')::date::timestamp at time zone 'Europe/London')
    ) / 1800))::int
{%- endmacro %}
