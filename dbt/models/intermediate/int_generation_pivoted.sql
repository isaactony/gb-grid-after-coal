-- Transmission-metered generation per half hour, pivoted to one column per fuel group (MW).

{% set groups = dbt_utils.get_column_values(ref('fuel_types'), 'fuel_group', order_by='min(sort_order)') %}

select
    g.settlement_date,
    g.settlement_period,
    {% for grp in groups %}
    sum(g.generation_mw) filter (where f.fuel_group = '{{ grp }}')   as {{ grp | lower | replace(' ', '_') }}_mw,
    {% endfor %}
    sum(g.generation_mw) filter (where not f.is_interconnector)      as domestic_generation_mw,
    sum(g.generation_mw)                                             as total_supply_mw,
    count(*)                                                         as fuel_rows
from {{ ref('stg_elexon__generation_by_fuel') }} as g
left join {{ ref('fuel_types') }} as f using (fuel_type_code)
group by 1, 2
