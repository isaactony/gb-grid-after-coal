"""Land raw API responses from Elexon and Carbon Intensity into raw.api_responses.

Responses are stored untouched (jsonb) and append-only, one row per request window.
All parsing, typing and de-duplication happens downstream in dbt.

Usage:
    python -m ingest                       # incremental: new windows + re-fetch the last 7 days (revisions)
    python -m ingest --source elexon_fuelhh --start 2017-01-01
    python -m ingest --force --start 2024-03-25 --end 2024-04-05
"""

import argparse
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta

import psycopg
import requests
from dotenv import load_dotenv

ELEXON = "https://data.elexon.co.uk/bmrs/api/v1"
CARBON = "https://api.carbonintensity.org.uk"

# name -> (earliest date, days per request, url builder)
SOURCES = {
    "elexon_fuelhh": (
        date(2017, 1, 1), 7,
        lambda s, e: f"{ELEXON}/datasets/FUELHH?settlementDateFrom={s}&settlementDateTo={e}&format=json",
    ),
    "elexon_demand_outturn": (
        date(2017, 1, 1), 7,
        lambda s, e: f"{ELEXON}/demand/outturn?settlementDateFrom={s}&settlementDateTo={e}&format=json",
    ),
    "elexon_market_index": (
        date(2017, 1, 1), 6,
        lambda s, e: f"{ELEXON}/balancing/pricing/market-index?from={s}T00:00Z&to={e + timedelta(days=1)}T00:00Z&format=json",
    ),
    "carbon_national_intensity": (
        date(2017, 9, 26), 30,
        lambda s, e: f"{CARBON}/intensity/{s}T00:00Z/{e + timedelta(days=1)}T00:00Z",
    ),
    "carbon_national_generation": (
        date(2018, 5, 11), 30,
        lambda s, e: f"{CARBON}/generation/{s}T00:00Z/{e + timedelta(days=1)}T00:00Z",
    ),
    "carbon_regional": (
        date(2018, 5, 11), 13,
        lambda s, e: f"{CARBON}/regional/intensity/{s}T00:00Z/{e + timedelta(days=1)}T00:00Z",
    ),
}

DDL = """
CREATE TABLE IF NOT EXISTS raw.api_responses (
    response_id   bigserial PRIMARY KEY,
    source        text        NOT NULL,
    window_start  date        NOT NULL,
    window_end    date        NOT NULL,
    request_url   text        NOT NULL,
    http_status   int         NOT NULL,
    record_count  int,
    fetched_at    timestamptz NOT NULL DEFAULT now(),
    payload       jsonb
);
CREATE INDEX IF NOT EXISTS api_responses_source_window ON raw.api_responses (source, window_start);
"""

LOOKBACK_DAYS = 7  # Elexon re-publishes recent figures; always re-fetch the tail.
session = requests.Session()
session.headers["User-Agent"] = "gb-grid-after-coal portfolio project (github)"


def connect():
    load_dotenv()
    return psycopg.connect(
        host=os.environ["WAREHOUSE_HOST"], port=os.environ["WAREHOUSE_PORT"],
        dbname=os.environ["WAREHOUSE_DB"], user=os.environ["WAREHOUSE_USER"],
        password=os.environ["WAREHOUSE_PASSWORD"],
    )


def windows(start, end, step):
    s = start
    while s <= end:
        yield s, min(s + timedelta(days=step - 1), end)
        s += timedelta(days=step)


def fetch(url, attempts=5):
    for i in range(attempts):
        try:
            r = session.get(url, timeout=120)
            if r.status_code in (429, 500, 502, 503, 504):
                raise requests.HTTPError(f"retryable {r.status_code}")
            return r.status_code, (r.json() if r.content else None)
        except (requests.RequestException, ValueError):
            if i == attempts - 1:
                raise
            time.sleep(2 ** i)


def count_records(payload):
    data = payload.get("data") if isinstance(payload, dict) else payload
    return len(data) if isinstance(data, list) else None


def run(source, start, end, force, workers):
    earliest, step, build_url = SOURCES[source]
    start = max(start, earliest)
    with connect() as conn:
        done = {
            row[0] for row in conn.execute(
                "SELECT DISTINCT window_start FROM raw.api_responses "
                "WHERE source = %s AND http_status = 200 AND record_count > 0", (source,))
        }
    tail = date.today() - timedelta(days=LOOKBACK_DAYS)
    todo = [(s, e) for s, e in windows(start, end, step) if force or s not in done or e >= tail]
    print(f"{source}: {len(todo)} windows to fetch ({start} → {end}, {step}-day windows)", flush=True)

    ok = failed = rows = 0
    with ThreadPoolExecutor(max_workers=workers) as pool, connect() as conn:
        futures = {pool.submit(fetch, build_url(s, e)): (s, e) for s, e in todo}
        for f in as_completed(futures):
            s, e = futures[f]
            url = build_url(s, e)
            try:
                status, payload = f.result()
            except Exception as exc:  # noqa: BLE001 — log and carry on; next run retries the window
                failed += 1
                print(f"  FAILED {source} {s}: {exc}", flush=True)
                continue
            n = count_records(payload)
            conn.execute(
                "INSERT INTO raw.api_responses (source, window_start, window_end, request_url, http_status, record_count, payload) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (source, s, e, url, status, n, json.dumps(payload)),
            )
            conn.commit()
            ok += status == 200
            failed += status != 200
            rows += n or 0
            if (ok + failed) % 50 == 0:
                print(f"  {source}: {ok + failed}/{len(todo)} windows", flush=True)
    print(f"{source}: done — {ok} ok, {failed} failed, {rows:,} records", flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source", choices=SOURCES, action="append", help="default: all sources")
    p.add_argument("--start", type=date.fromisoformat, default=date(2017, 1, 1))
    p.add_argument("--end", type=date.fromisoformat, default=date.today())
    p.add_argument("--force", action="store_true", help="re-fetch windows already loaded")
    p.add_argument("--workers", type=int, default=4)
    args = p.parse_args()

    with connect() as conn:
        conn.execute(DDL)
    for source in args.source or SOURCES:
        run(source, args.start, args.end, args.force, args.workers)


if __name__ == "__main__":
    main()
