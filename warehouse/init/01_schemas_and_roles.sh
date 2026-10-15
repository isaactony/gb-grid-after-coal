#!/usr/bin/env bash
# Runs once, when the warehouse volume is first created.
set -euo pipefail
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v reader_pw="$METABASE_READER_PASSWORD" <<'SQL'
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS marts;

-- Read-only login for the BI layer: it can see the marts schema and nothing else.
CREATE ROLE metabase_reader LOGIN PASSWORD :'reader_pw';
GRANT CONNECT ON DATABASE grid TO metabase_reader;
GRANT USAGE ON SCHEMA marts TO metabase_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA marts GRANT SELECT ON TABLES TO metabase_reader;
SQL
