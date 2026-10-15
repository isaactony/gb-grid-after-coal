-- National generation mix (% of generation) per half hour, including embedded solar and wind
-- estimates that Elexon's FUELHH does not cover. Pivoted wide: one column per fuel.

{% set fuels = ['biomass', 'coal', 'imports', 'gas', 'nuclear', 'other', 'hydro', 'solar', 'wind'] %}

with records as (
    {{ raw_records('carbon_national_generation') }}
),

typed as (
    select
        (rec ->> 'from')::timestamptz as half_hour_start_utc,
        (select jsonb_object_agg(m ->> 'fuel', (m ->> 'perc')::numeric)
           from jsonb_array_elements(rec -> 'generationmix') as m) as mix,
        fetched_at
    from records
)

select distinct on (half_hour_start_utc)
    half_hour_start_utc,
    {% for f in fuels %}
    (mix ->> '{{ f }}')::numeric as {{ f }}_pct{{ "," if not loop.last }}
    {% endfor %}
from typed
order by half_hour_start_utc, fetched_at desc
