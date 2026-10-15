-- What the loader has fetched: one row per source per fetch day.

select
    source,
    fetched_at::date                                    as fetch_date,
    count(*)                                            as requests,
    count(*) filter (where http_status <> 200)          as failed_requests,
    sum(record_count)                                   as records,
    min(window_start)                                   as earliest_window,
    max(window_end)                                     as latest_window,
    max(fetched_at)                                     as last_fetched_at
from {{ source('raw', 'api_responses') }}
group by 1, 2
