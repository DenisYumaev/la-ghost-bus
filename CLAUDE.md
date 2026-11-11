# CLAUDE.md — LA Ghost Bus Tracker

Instructions for Claude Code working in this repo. Read this, `docs/SPEC.md`, and every file in `docs/decisions/` before making changes.

## What this project is

A continuously running pipeline that measures how much scheduled LA Metro bus service never runs, and splits it into cancellations Metro announced in advance and unplanned ones. The full design is in `docs/SPEC.md`. Accepted decisions live in `docs/decisions/`; follow them, and never contradict one silently.

## Who you're working with

The owner is a stats and data science student building this as a portfolio project for data engineering internships. Two goals carry equal weight: a project that holds up in a senior engineer's code review, and the owner learning to defend every line in an interview.

So:

- **Explain each non-trivial choice in one or two sentences as you make it**, including the main alternative you rejected.
- **Do not write the core logic unless asked.** The owner writes these by hand: the dbt SQL models for trip matching and outcome classification, the missed-trip rules, and the statistics (cluster bootstrap). Scaffold the files, write tests that pin the expected behavior, and leave the implementation as a clearly marked TODO. Boilerplate (Docker, Terraform, CI, config, the poller's HTTP and storage plumbing) is yours to write.
- **When the owner asks you to review their code**, review like a staff engineer: correctness, failure modes, idempotency, naming, tests. Point out problems; don't silently rewrite.

## Hard rules

1. **Bronze is sacred.** Never write code that modifies or deletes files in the bronze layer. Raw responses are stored byte-for-byte (ADR-001, decision 2).
2. **Every job must be idempotent.** Running anything twice must produce the same result. Bronze writes are keyed on content hash; silver and gold overwrite whole service-date partitions.
3. **Terraform: always show `terraform plan` and wait for explicit approval before `apply` or `destroy`.** Never add NAT gateways, more than one EC2 instance, or instance types larger than t4g.medium without asking. The bronze S3 bucket must have `prevent_destroy` and versioning on.
4. **AWS credentials:** use the configured AWS profile. Never create IAM users or access keys, never print credentials, never commit `*.tfstate`, `.env`, or keys.
5. **Times are stored in UTC.** Service dates follow the GTFS rule in `America/Los_Angeles`; times can exceed 24:00 (ADR-001, decision 5).
6. **Never join sources on `trip_id` directly.** Go through the trip crosswalk (ADR-001, decision 4).
7. **Tests run offline** against fixtures in `tests/fixtures/`. No test may make a network call.
8. **A decision that changes an accepted ADR gets a new ADR** that supersedes it. Don't edit accepted ADRs.

## Stack

Python 3.12 with uv · ruff · pytest · DuckDB · dbt (dbt-duckdb) · Docker Compose · Terraform · GitHub Actions. Airflow arrives in week 3, Redpanda and Iceberg in week 4. Don't add them earlier.

## Layout

```text
ingest/          poller, fetch log, schema fingerprints (stream consumer later)
dbt/models/      bronze/ silver/ gold/
dags/            Airflow DAGs (week 3)
analysis/        statistics and findings notebooks
dashboard/       Evidence or Streamlit
infra/           Terraform
tests/fixtures/  real snapshots recorded once, committed
scripts/         one-off tools such as day1_probe.py
docs/            SPEC.md, decisions/, runbook.md
```

## Commands

- `make up` — start the local stack
- `make test` — run all tests offline
- `make lint` — ruff and type checks
- `make backfill START=YYYY-MM-DD END=YYYY-MM-DD` — rebuild from bronze (once it exists)

## Commits and PRs

One PR per meaningful change. Each PR description says what changed, why, how it was tested, and which ADR it relates to.
