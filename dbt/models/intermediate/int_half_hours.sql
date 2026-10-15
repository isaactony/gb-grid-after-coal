-- One row per half-hour from the project start to now: the spine every fact joins to.
--
-- GB electricity is settled in local (Europe/London) half-hour "settlement periods", numbered
-- from 1 at local midnight. When the clocks go forward a settlement day has 46 periods; when
-- they go back it has 50. Elexon reports in settlement date/period, Carbon Intensity in UTC;
-- this spine is what lines the two up.

with spine as (
    select generate_series(
        ('{{ var("start_date") }}'::timestamp at time zone 'Europe/London'),
        date_trunc('hour', now()),
        interval '30 minutes'
    ) as half_hour_start_utc
),

local_time as (
    select
        half_hour_start_utc,
        half_hour_start_utc at time zone 'Europe/London' as half_hour_start_local
    from spine
)

select
    half_hour_start_utc,
    half_hour_start_local,
    {{ settlement_date_from_utc('half_hour_start_utc') }}              as settlement_date,
    {{ settlement_period_from_utc('half_hour_start_utc') }}            as settlement_period,
    extract(hour from half_hour_start_local)::int                       as local_hour,
    extract(isodow from half_hour_start_local)::int                     as local_iso_dow
from local_time
