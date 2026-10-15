{#
  Unnest the `data` array of every successful response for one source.
  On incremental runs only responses newer than those already processed are read.
#}
{% macro raw_records(source_name) -%}
    select
        r.response_id,
        r.fetched_at,
        rec
    from {{ source('raw', 'api_responses') }} as r
    cross join lateral jsonb_array_elements(r.payload -> 'data') as rec
    where r.source = '{{ source_name }}'
      and r.http_status = 200
    {% if is_incremental() %}
      and r.response_id > (select coalesce(max(source_response_id), 0) from {{ this }})
    {% endif %}
{%- endmacro %}
