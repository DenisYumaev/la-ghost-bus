# ADR-002: Compressed timeline, scope, and operating standards

- **Status:** Accepted
- **Date:** 2026-11-10
- **Scope:** Delivery timeline, how agent-written code is accepted, reliability targets, incident handling, when new tools are adopted, an LLM extraction component, and dataset publishing
- **Relates to:** Replaces the spec's "Six-week plan" section. Streaming has its own record, ADR-003. Does not change any ADR-001 decision.

## Context

The spec planned six weeks at 50 to 60 hours each, written before two facts were known:

1. **The owner will build with Claude Code**, so plumbing (Terraform, Docker, CI, poller I/O, Airflow wiring) goes much faster. Day 1, the full repo with CI, Terraform, and applied infrastructure, took one session.
2. **Internship recruiting for summer 2027 is happening now.** Many mid-sized companies hire between January and March, so a live link in late November is worth more than a finished system in February.

Two things don't speed up with more effort:

- **Data accrues in real time.** The cluster bootstrap resamples whole service days, so precision depends on how many days exist. November is a partial month because archiving starts Nov 11, so the first full-month reconciliation against Metro's report is for December, published in early January. Metro sets the date of the service change.
- **Understanding.** An agent can write a week of code in an afternoon; the owner still has to defend every line in a deep-dive interview. Code the owner can't explain doesn't help the project's purpose.

## Decision 1: Milestones by date, with findings gated on data rather than effort

| By | Build | Done when |
| --- | --- | --- |
| **Nov 14** | Poller 24/7 on one VM (Metro realtime, canceled service, fetch log, external heartbeat). GTFS static in DuckDB. Owner writes schedule expansion SQL. Request the Swiftly key. Confirm the service-change date. | Archive running; "how many trips did line 754 schedule yesterday?" answered in SQL |
| **Nov 21** | dbt bronze to silver to gold; matching v1 through the crosswalk; ran, missed, and unknown outcomes; nightly compaction; dbt every 10 minutes on cron; dashboard v1; README v1; SLO measurement starts | **Public link live. Resume line exists; start applying.** |
| **Nov 30** | Airflow (retries, backfill DAG); block inference, partial trips, schedule versioning, schema-drift detection; full tests, alerts, and runbook; SLO tile on the dashboard; baseline real-time detector (ADR-003) | One-command backfill works; SLOs reported daily; baseline detector precision measured |
| **Dec 15** | Swiftly into Redpanda: archiver plus stateful detector (ADR-003). LLM alert-cause extraction (decision 6) if the probe confirms usable alert text. Fuzzy matching. Iceberg only if decision 5 triggers. | ADR-003 acceptance criteria met; extractor meets its eval bar |
| Mid-Dec (date to confirm) | Metro service change goes live | Prior-month numbers unchanged; new trip IDs matched |
| **Jan 15** | December reconciliation; cluster-bootstrap intervals over about 60 days; equity analysis; hand-validate 50 trips; threshold sensitivity; dataset release (decision 7); launch post; pitch two advocacy groups or reporters | Three findings with method and validation; mock deep-dive interview passed cold |

**Why dates and not weeks:** the hard constraints are calendar-bound (recruiting season, a full month of data, the service change), so the plan says when, not how long.

**Cut order if time slips:** shape projection, fuzzy matching, the equity analysis, then LLM extraction. If streaming is cut, the product falls back to the baseline detector (ADR-003). Never cut the Nov 30 reliability milestone, and never stop the poller.

**Alternatives considered:** keeping the six-week plan (it delivers the impressive parts after most applications are in), or finishing everything before applying (findings can't be final before mid-January anyway).

## Decision 2: Agent-written code merges only after the owner explains it back

**Decision.** CLAUDE.md's split stands: the owner hand-writes trip matching, outcome classification, missed-trip rules, and statistics; Claude writes plumbing. In addition, **no PR containing agent-written code merges until the owner can explain it**: what it does, why that approach, and what would break it. Claude asks those questions in the PR review; anything the owner can't answer is reworked or explained until they can.

Weekly, the owner answers the spec's "questions you must answer cold" without notes.

**Why.** The bottleneck is now understanding, not typing. This turns agent speed into learning instead of breadth that can't be defended. The guardrails themselves (CLAUDE.md hard rules, decision records, plan-before-apply, branch protection, network-blocked tests) are also an interview story: how to run a coding agent safely against real infrastructure.

**Alternatives considered:** no gate (fast, but the code stops being the owner's), or the owner writing everything (slow, and plumbing teaches little).

## Decision 3: Service-level objectives with an error budget

| SLO | Target | Measured as |
| --- | --- | --- |
| Feed freshness | 99.5% of minutes, per realtime feed, per calendar month | Minutes with a successful fetch whose header timestamp is under 3 minutes old (the spec's "healthy") |
| Cancellation capture | 99.5% of minutes, per month | Minutes with a successful canceled-service fetch |
| Trip match rate | 95% or more per day, per source | Matched observations over all observations (ADR-001 decision 4) |
| Dashboard freshness | Gold data under 15 minutes old, 99% of the time | Age of the newest gold partition when sampled |

**Error budget:** 0.5% of a 30-day month is 216 minutes. If a month's budget is spent, feature work stops until the cause is fixed and a postmortem is written (decision 4).

**Why.** "It runs continuously" is a claim; "it met a 99.5% freshness SLO for 90 days" is evidence. SLOs also make the fetch log useful as a metric, and the budget policy is how real teams trade reliability against features.

**Alternatives considered:** alerts without SLOs (they say something broke, not whether the system is reliable), or a 99.9% target (43 minutes a month, unrealistic for one VM without redundancy).

## Decision 4: Incident log with blameless postmortems

**Decision.** Every incident gets a file in `docs/incidents/YYYY-MM-DD-slug.md` using the template there. Each one records what happened, impact (data lost or delayed, in minutes), detection, timeline in UTC, root cause, what went well and badly, and action items with PR links.

An incident is any of:
- an SLO breach
- a gap in bronze not explained in the fetch log
- any manual action on production data
- a bad number reaching the public dashboard

**Why.** Real failures will happen: Metro's API is in beta, disks fill up, cron fails silently. A written postmortem of a real failure is the most persuasive reliability evidence in an interview, more than any planned chaos drill.

## Decision 5: Tools are adopted on evidence, each with its own ADR

**Decision.** Airflow stays on the plan (Nov 30): backfills and retries are certain to be needed. **Iceberg is adopted only when one of these happens:**

- Daily compaction plus plain Parquet causes a measured problem with too many small files or slow queries.
- A schema change in a feed needs evolution that plain Parquet partitions handle badly.
- A consumer needs atomic multi-file commits, for example concurrent writers.

If adopted, the catalog choice (AWS Glue or a SQL catalog) and its cost go in the ADR. Iceberg needs a catalog, which the original spec didn't mention.

**Why.** "Why Iceberg over plain Parquet?" (spec question 6) is answered best by "here is the problem I hit." Adopting it ahead of a problem gives no such answer.

## Decision 6: LLM extraction of service-alert causes, gated on the probe

**Decision.** If the day-1 probe shows Metro publishes service-alert text, build a small extraction pipeline that turns each alert into structured fields: cause category (operator shortage, mechanical, traffic, detour, weather, other), affected lines, and start and end times. Output goes to silver as `stg_alert_causes` and joins to trip outcomes, adding a "why" next to "how much."

Design rules:
- **Raw alert text lands in bronze** like every other source (ADR-001 decision 2).
- **Idempotent by caching, not by determinism.** LLM output isn't deterministic, so results are stored and keyed on `(alert_content_hash, prompt_version, model)`. Backfills reuse stored results, and the model is called again only when the prompt or model version changes. Duplicate alerts never cost a second call.
- **Structured outputs** constrain the response to the schema; no free-text parsing.
- **An eval set comes first:** 200 alerts the owner labels by hand, scored for per-category precision and recall and for exact-match on lines. The extractor ships only at 0.9 or higher category precision.
- **Model choice is the owner's, made on the eval.** Start with `claude-opus-5-5` as the quality reference and test `claude-haiku-5-5` against it. Daily extraction isn't time-sensitive, so it uses the Message Batches API (50% off).
- **Spend cap:** a monthly limit set in the Anthropic Console. This is billed separately from the AWS budget.

**Cost estimate** (Anthropic list prices, before the batch discount): per unique alert, about 1,500 input tokens and about 350 output tokens including low-effort thinking.

| Unique alerts/day | `claude-opus-5-5` ($4 / $20 per MTok) | `claude-haiku-5-5` ($0.10 / $0.50 per MTok) |
| --- | --- | --- |
| 50 | about $20 a month, about $10 batched | about $0.50 a month |
| 300 | about $117 a month, about $58 batched | about $3 a month |

The probe measures the real unique-alert volume before the model is chosen. Hashing out duplicate alerts is the biggest cost lever.

**Why.** Turning unstructured text into structured data, with evals, cost control, and reproducibility, is what AI startups' data teams do daily. Here it serves the project's question instead of being bolted on.

**Alternatives considered:**
- Regex or keyword rules: brittle on free text, but kept as a baseline in the eval for comparison.
- Fine-tuning a small model: needs far more labels than this project will have.
- No AI component: the project is strong without it, but this is the cheapest relevant signal for AI-startup roles.

**Would change if:** the probe finds no alert text, or alerts carry no information about causes. Then the decision is withdrawn in a new ADR.

## Decision 7: Publish the dataset on Hugging Face as well as S3

**Decision.** The January dataset release (Parquet, data dictionary, method notes, credit to LA Metro per its terms) is also published as a Hugging Face dataset, versioned per release.

**Why.** It costs nothing extra, and it's where ML and AI-startup engineers look for datasets. The S3 copy remains the source.

## Consequences

- The spec's "Six-week plan" section is replaced with this timeline; its learning track and chaos drills carry over per milestone.
- CLAUDE.md gains the explain-back rule and updated tool arrival dates.
- New files: `docs/incidents/` (template), and later `fct_ghost_alerts` (ADR-003) and `stg_alert_causes` (decision 6).
- Open questions for the probe: does alert text exist, and how many unique alerts are there per day?
