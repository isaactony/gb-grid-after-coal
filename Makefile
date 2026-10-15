# Load .env into every recipe so dbt and the loader see the warehouse credentials.
SHELL := /bin/bash
ENV := set -a && source .env && set +a
DBT := $(ENV) && cd dbt && DBT_PROFILES_DIR=. ../.venv/bin/dbt

.PHONY: setup up ingest build test docs

setup:            ## Create the virtualenv and install dbt packages
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	$(DBT) deps

up:               ## Start the Postgres warehouse
	docker compose up -d warehouse

ingest:           ## Fetch new data (and re-fetch the last 7 days for revisions)
	$(ENV) && .venv/bin/python -m ingest

build:            ## Seed, run and test every model
	$(DBT) build

test:
	$(DBT) test

docs:             ## Generate and serve dbt docs on http://localhost:8080
	$(DBT) docs generate && $(DBT) docs serve --port 8080
