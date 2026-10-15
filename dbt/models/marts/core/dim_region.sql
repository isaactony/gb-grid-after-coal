with regions as (
    select distinct on (region_id) region_id, region_name, dno_region
    from {{ ref('stg_carbon_intensity__regional_intensity') }}
    order by region_id, half_hour_start_utc desc
)

select
    r.region_id,
    r.region_name,
    r.dno_region,
    s.region_type,
    s.nation
from regions as r
left join {{ ref('carbon_regions') }} as s using (region_id)
