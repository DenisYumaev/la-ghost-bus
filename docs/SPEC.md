# Ghost Bus Tracker — Project Spec

Nov 10, 2026 · Denis Y

## Summary

Build a continuously running data platform that measures how much scheduled LA Metro bus service never runs, and splits that loss into cancellations Metro announced in advance and ones it didn't.

**The question:** Of every bus trip LA Metro schedules, how many never run? Where and when does it happen, and who is affected? How much of it falls outside Metro's canceled-service feed, which by design lists only scheduled cancellations (an operator calling out sick) and not unplanned ones (a bus breaking down)?

**One-line pitch:** "I measured how much LA bus service disappears without warning, using a pipeline I've run continuously since November 2026."

**Done looks like:**

- Every feed snapshot archived since week 1, with every gap logged and explained
- A public dashboard showing missed-trip rates by line, hour, and neighborhood, refreshed at least every 10 minutes
- Monthly per-line totals that reconcile with Metro's own published cancellation report, within a stated tolerance
- A documented public dataset (Parquet) that advocates and researchers can download and use
- A repo a senior engineer would approve: tests, CI, infrastructure as code, decision records, a runbook
- Three findings, each with its method written down and hand-verified
- You can answer every question in "Questions you must answer cold" without notes

## Why this stands out

Transit pipelines exist; what doesn't exist is this question answered with this rigor. Similar portfolio projects stream MBTA, NYC, or Hong Kong feeds into a live map. This one differs in four ways:

| Typical transit project | This project |
| --- | --- |
| Shows where buses are right now | Measures trips that never appeared at all, which is the harder join |
| Runs for a weekend demo | Archives continuously; by spring it holds months of history nobody else has |
| Trusts whatever the feed says | Separates cancellations Metro announced from unplanned ones, which Metro's own feed leaves out by design |
| No users | Publishes a documented dataset and findings that advocates and reporters can cite |

The problem is real and documented. In January 2022, nearly 1 in 6 LA Metro bus trips were canceled during an operator shortage, and TransitCenter notes that ghost-bus data is hard to find because canceled trips produce no GPS signal ([TransitCenter](https://transitcenter.org/ghost-buses-are-haunting-riders-across-america/)). King County passed legislation in 2025 asking its transit agency to report ghost buses ([King County Council](https://kingcounty.gov/es-es/dept/council/governance-leadership/county-council/newsroom/2025/03-04-balducci-baron-perry-ghost-bus-passage-release)).

## Data sources

Six free sources, all checked in November 2026. Metro's API is officially in beta, and Metro warns that its URLs and field names may change, so the pipeline must detect schema drift rather than assume it away.

| Source | What it gives you | Refresh | Role in the project |
| --- | --- | --- | --- |
| [GTFS static (bus)](https://gitlab.com/LACMTA/gtfs_bus) | The schedule: routes, trips, blocks, stops, stop times, calendars. Download URL `https://gitlab.com/LACMTA/gtfs_bus/raw/master/gtfs_bus.zip` ([Mobility Database](https://mobilitydatabase.org/feeds/gtfs/mdb-29)) | calendar_dates.txt weekly; full schedule at each service change | Ground truth for what should run |
| [Transitland feed archive](https://transit.land/feeds/f-9q5-metro~losangeles) | Over 100 archived versions of Metro's bus schedule | As Metro publishes | Lets you reconstruct which schedule was in force on any past date |
| GTFS-rt Vehicle Positions + Trip Updates | Where each bus is and which trip it claims to run. Metro's realtime feeds come from Swiftly, with agency keys `lametro` (bus) and `lametro-rail` ([Metro developer page, mirrored](https://backiee.wasmer.app/https_developer_metro_net/api)) | Every minute via the [Metro API](https://api.metro.net); faster via Swiftly directly | Evidence of what actually ran |
| [Canceled service feed](https://lacmta.github.io/metro-api-v2/docs/intro) | Currently scheduled cancellations: `/canceled_service_summary`, `/canceled_service/all`, `/canceled_service/line/{line}` | About every 5 minutes per the developer page; 15 minutes per the API home page | What Metro announced in advance |
| [Monthly bus cancellation report](https://www.metro.net/riding/nextrip/) | Percentage of trips canceled per bus line | Monthly | Independent validation of your totals |
| US Census ACS 5-year + Metro's Equity Focus Communities map | Income and car ownership by tract; Metro's own equity geography | Yearly | Who is affected |

Three facts from Metro's own documentation shape the design ([developer page, mirrored](https://backiee.wasmer.app/https_developer_metro_net/api)):

- **The canceled-service feed lists scheduled cancellations only**, such as an operator calling out sick, and excludes unplanned ones like a breakdown. Never describe the gap between your numbers and this feed as Metro hiding data. The gap is the unplanned share, and measuring it is your contribution.
- **The feed lists only currently scheduled cancellations.** Entries likely disappear once trips pass, so it must be polled continuously and every snapshot kept, or that history is lost for good.
- **Contracted lines are excluded** from the cancellation feed and the monthly report. Metro lists them: 96, 125, 128, 130, 167, 177, 205, 218, 232, 256, 266, 501, 577, 603, 605 ([Metro](https://www.metro.net/riding/nextrip/)). Scope every headline metric to Metro-operated lines so all three sources compare like with like.

Use Metro's Equity Focus Communities definition for the equity analysis rather than inventing your own. Metro's board reports already break cancellations down by the share of each line's miles in those communities ([Metro board report, Feb 2026](https://datamade-metro-pdf-merger.s3.amazonaws.com/2026-0066.pdf)), so your numbers can be compared directly with theirs.

## Architecture

v1 is a micro-batch pipeline. v2 adds a streaming path that has one job: a real-time ghost-bus detector that flags trips likely missing *right now* (ADR-003). Both paths land in the same bronze layer, so every model downstream is shared. Milestone dates are in ADR-002.

```text
Metro API (1 min) ─┐                       Swiftly (5-10 s, by Dec 15)
Service alerts ────┤                                │
GTFS static ───────┤                                ▼
                   ▼                       Redpanda (7-day replay)
            Python poller                  ├─► bronze archiver
            (cron → Airflow)               ├─► ghost detector ◄── today's trips
                   │                       │   (timers, event time)  (dim_schedule_trips)
                   │                       └─► live metrics
                   │                                │
                   └──────────► Bronze: raw snapshots on S3 ◄──┘
                                (append-only, content-hash keys)
                                        │
                                        ▼
               Silver (dbt) ──► Gold (dbt) ◄── fct_ghost_alerts (scored nightly)
               + alert causes (LLM, cached)   │        │
                               Dashboard ◄────┘        └► Alerts + runbook
        Airflow orchestrates · Terraform defines AWS · CI on every PR
```

The census join and Metro's Equity Focus Communities map enter at the gold layer for the equity analysis. Bronze is compacted nightly: about 3,000 small snapshot files a day become one Parquet file per feed per service date, which keeps queries fast and S3 request costs low.

| Component | Choice | Why | Rejected and why |
| --- | --- | --- | --- |
| Language | Python 3.12, uv | Industry default for DE; uv for fast, locked installs | Poetry: slower, no real advantage here |
| Raw storage | S3; Iceberg only when a measured problem calls for it (ADR-002, decision 5) | Cheap, durable; Iceberg adds schema evolution and atomic commits, at the cost of running a catalog | Postgres for raw: expensive to keep months of snapshots |
| Query engine | DuckDB | Free, fast on a laptop, reads S3 and Iceberg directly | Snowflake: costs money; mention it as the scale-up path in a decision record |
| Transformations | dbt | The most requested DE tool in postings; tests and lineage built in | Raw SQL scripts: no tests, no lineage |
| Orchestration | Airflow | Most common orchestrator in job postings; adopted by Nov 30, once cron's lack of retries and backfills hurts | Dagster: arguably nicer, but fewer postings name it |
| Streaming | Redpanda + a plain Python stateful consumer | Needed by the ghost detector: absence detection with timers, event-time watermarks, 7-day replay for backtesting, one ingest feeding several consumers (ADR-003). Must beat a micro-batch baseline | Kafka: heavier to run. Flink: a JVM that doesn't fit the VM. Streaming into Iceberg with no requirement: resume-driven |
| LLM extraction | Claude API, structured outputs, Batch API | Turns service-alert text into cause categories; results cached by content hash; shipped only after passing an eval (ADR-002, decision 6) | Regex rules: brittle on free text, kept as the eval baseline |
| Dashboard | Evidence or Streamlit | SQL-native, free hosting options | Tableau: not code, can't be reviewed in a PR |
| Infrastructure | Terraform + GitHub Actions | Reproducible environments; CI on every PR | Console clicks: not reproducible |

Target cost: about $30 a month on AWS, with a billing alarm at $40, plus Anthropic API spend under a separate monthly cap set in the Console (ADR-002, decision 6). One small VM with 4 GB runs the poller, Airflow, and Redpanda, and S3 holds the data. That memory is tight: Airflow alone needs 2 to 3 GB, so run Redpanda at `--smp 1 --memory 1G`, measure, and ask before moving to a larger instance. Price the instance in the AWS pricing calculator by Nov 14 and record the real number in a decision record.

## Data model

Three layers, and only bronze is precious: everything downstream must be rebuildable from it alone. Every table carries `agency_id` from day one, so a second agency can be added later without a migration.

**Bronze (raw, append-only, never edited).** Exactly what the source returned, plus how the fetch went.

| Table | Grain | Key columns |
| --- | --- | --- |
| raw_fetch_log | One fetch attempt, success or failure | fetched_at, endpoint, http_status, latency_ms, bytes, error |
| raw_vehicle_positions | One feed snapshot | fetched_at, feed_header_timestamp, payload, content_hash |
| raw_trip_updates | One feed snapshot | same as above |
| raw_cancellations | One API response | fetched_at, payload, content_hash, schema_fingerprint |
| raw_gtfs_static | One schedule ZIP | downloaded_at, feed_version, file_hash |

The fetch log is what makes "unknown" possible: without a record of failed fetches, you can't tell an outage from a quiet feed.

**Silver (cleaned, typed, deduplicated).** One row per real-world fact.

| Table | Grain | Notes |
| --- | --- | --- |
| stg_vehicle_positions | vehicle × observation time | Deduplicated on (vehicle_id, vehicle timestamp); bad coordinates quarantined, not dropped |
| stg_trip_updates | trip × stop × observation | Latest prediction per stop, history retained |
| stg_cancellations | announced trip | First-seen and last-seen times, so you know how far in advance each cancellation was announced |
| dim_schedule_trips | trip × service date | Includes `block_id` (the chain of trips one bus runs) and handles times past 24:00; versioned so each date uses the schedule in force that day (SCD Type 2) |
| dim_stops, dim_routes, dim_shapes | entity × schedule version | Versioned like trips |
| int_trip_observations | scheduled trip × service date | First and last seen, furthest stop reached, vehicle IDs, match method and confidence |
| stg_alert_causes | service alert × prompt version | Cause category, affected lines, time window; extracted by an LLM, cached on `(content_hash, prompt_version, model)` (ADR-002, decision 6) |

**Gold (answers).** What the dashboard, dataset, and findings read.

| Table | Grain | Answers |
| --- | --- | --- |
| fct_trip_outcomes | scheduled trip × service date | Outcome (see methodology), announced in advance or not, how it was matched |
| fct_missed_rate_daily | route × direction × hour × day | Missed-trip rate, announced rate, unplanned rate, each with an interval |
| fct_feed_health | feed × 5 minutes | Freshness lag, record counts, fetch error rate, healthy flag |
| fct_slo_monthly | SLO × month | Target, achieved, error budget used (ADR-002, decision 3) |
| fct_ghost_alerts | trip × service date × detector version × event | Real-time flag and retraction events, scored nightly against `fct_trip_outcomes` for precision, recall, and latency (ADR-003) |
| fct_reconciliation_monthly | route × month | Your canceled rate against Metro's monthly report, and the difference |
| fct_equity_by_line | route × month | Lost service against the line's share of miles in Equity Focus Communities |
| fct_service_by_tract | census tract × month | Missed trips at the tract's stops, joined to ACS income and car ownership; feeds the neighborhood view on the dashboard |

`fct_trip_outcomes` is the heart of the project. Every other gold table aggregates it, which keeps every number consistent with every other.

## Missed-trip methodology

A trip counts as missed only when the feed was healthy, the trip never appeared, and nothing suggests it ran untracked. The two traps are feed outages and buses running with broken GPS transponders; TransitCenter notes that agencies cite exactly that second problem as a reason not to publish this data ([TransitCenter](https://transitcenter.org/ghost-buses-are-haunting-riders-across-america/)).

**Step 1: Expand the schedule.** List every trip that should run on each service date, using the schedule version in force that day. GTFS times can exceed 24:00; a trip at 25:10 belongs to the previous service date.

**Step 2: Match observations to trips.** Match on `trip_id` first. Metro's trip IDs embed a service-change tag such as `SEPT21` ([Metro GTFS notes](https://lacmta.github.io/gtfs-bus)), so IDs change at every service change; always match against the version in force. When the ID is missing or unknown, fall back to route, direction, and start time within ±10 minutes. Record match method and confidence, and track the daily match rate as a health metric.

**Step 3: Measure how far each trip got.** Use the furthest stop sequence reached in trip updates or vehicle positions. Projecting GPS points onto route shapes is the week-4 upgrade if stop sequences prove unreliable.

**Step 4: Classify each trip.**

- **Ran:** reached at least 80% of its scheduled stops
- **Partial:** appeared but reached fewer than 80% of its stops
- **Likely ran, untracked:** never appeared, but the bus on the same block was observed on the trips immediately before and after it. Reported separately, never counted as missed. A block's first and last trips have only one neighbor, so they can't be inferred this way and fall through to the rules below.
- **Missed:** never appeared, no block evidence, feed healthy
- **Unknown:** never appeared, and the feed was healthy for less than 90% of the trip's window. A trip observed running during an outage is still classified by what was observed. Healthy means a successful fetch with a header timestamp under 3 minutes old.

Every threshold above is a starting point. Tune each against hand-checked trips and record the final values in a decision record.

**Step 5: Cross with what Metro announced.**

| | Announced in canceled-service feed | Not announced |
| --- | --- | --- |
| **Ran** | Announced but ran (reinstated, or a data error) | Normal service |
| **Missed** | Announced cancellation | **Unplanned missed trip: the headline metric** |

For announced cancellations, also report advance notice: scheduled start minus the time the cancellation first appeared in the feed.

**Step 6: Compute rates with honest uncertainty.**

```text
missed rate = missed trips / (scheduled trips - unknown trips)
```

Trips on the same day share causes, such as an operator shortage at one division, so they are not independent, and a standard Wilson interval would be too narrow. Use a cluster bootstrap that resamples whole service days. Hide any route-hour with fewer than 30 trips. Explaining this choice in an interview is where your stats background shows.

**Validation before publishing any finding:**

- Hand-trace 20 missed, 20 ran, and 10 likely-untracked trips through raw bronze data
- Reconcile monthly per-line canceled rates against Metro's published report; first find out exactly what Metro's report counts, then explain every line that differs by more than 2 percentage points
- Show the headline result at 70%, 80%, and 90% stop-coverage thresholds; a finding that flips under a reasonable threshold is not a finding

## Reliability and data quality

Every job must be safe to run twice, safe to run late, and safe to run for any past date. These are the properties interviewers probe most.

**Idempotency.** Bronze writes are keyed on `content_hash`, so re-fetching an identical snapshot is a no-op. Silver and gold rebuild whole service-date partitions with overwrite semantics, never blind appends.

**Backfills.** One command rebuilds any date range from bronze with no network calls: `make backfill START=2026-11-15 END=2026-11-20`. When matching logic changes, all history is recomputed with it.

**Late and out-of-order data.** Partition by service date, not arrival time. A service date stays open until 3 hours after its last scheduled trip ends; then its gold rows are finalized. Later arrivals still land in bronze and are flagged.

**Schedule changes.** Each new GTFS ZIP becomes a new schedule version with valid-from and valid-to dates; old versions are never overwritten. Metro has historically changed service in June and December, so a service change may land during the project. Confirm the date by Nov 14; it is the best possible live test of your versioning.

**Schema drift.** Metro's API is in beta. Fingerprint each response's field names and types; on any change, keep landing raw data, alert, and pause downstream models for that feed until a person approves the new shape.

**Watching the watcher.** The poller pings an external heartbeat service on every successful fetch. If the VM itself dies, your in-pipeline alerts die with it; the external check doesn't.

**Service-level objectives.** Reliability is measured, not asserted (ADR-002, decision 3): feed freshness and cancellation capture at 99.5% of minutes per month, trip match rate at 95% or more per day, and dashboard data under 15 minutes old 99% of the time. When a month's 216-minute error budget is spent, feature work stops until the cause is fixed. Every incident gets a blameless postmortem in `docs/incidents/` (ADR-002, decision 4).

**Tests (minimum set):**

- Schema and type checks on every silver table (dbt tests)
- Uniqueness: one row per scheduled trip per service date in `fct_trip_outcomes`
- Reconciliation: scheduled = ran + partial + likely-untracked + missed + unknown, exactly, every day
- Edge cases in unit tests: trips past 24:00, the March 2027 daylight-saving change, a trip ID that changes at a service change, a duplicate snapshot, an empty feed response
- Freshness: alert if bronze receives no snapshot for 5 minutes
- Volume: alert if vehicles in service fall outside the baseline for that hour and weekday
- Streaming: replaying the same offsets twice produces identical `fct_ghost_alerts`; a timer fires for a trip with no events at all
- All tests run offline against recorded fixtures: real snapshots saved once and committed to the repo

**Alerting and runbook.** Alerts go to Discord or email, and each links to a runbook entry: what it means, how to check, how to recover.

## Plan

Milestones are dated, not weekly, because the hard constraints are calendar-bound: recruiting season is now, the first full month of data is December, and Metro sets the service-change date (ADR-002, decision 1). Building goes fast with Claude Code. **Findings are gated on data accruing, not on effort.** Archiving starts first: the canceled-service feed shows only current cancellations, so every day not archived is history lost for good.

| By | Build | Done when | Chaos drill | Learning track |
| --- | --- | --- | --- | --- |
| Nov 14 | Poller 24/7 on one VM (Metro realtime, canceled service, service alerts, fetch log, external heartbeat). GTFS static in DuckDB. Owner writes schedule expansion SQL by hand. Request the Swiftly key. Confirm the service-change date | Archive running 24/7; you can answer "how many trips did line 754 schedule yesterday?" in SQL | Kill the poller for an hour; confirm the gap shows in the fetch log | SQL: joins, GROUP BY, CTEs. DDIA ch. 3 |
| Nov 21 | dbt bronze to silver to gold. Matching v1 through the crosswalk. Ran, missed, and unknown outcomes. Nightly compaction. Cron runs dbt every 10 minutes. Dashboard v1. README v1. SLO measurement starts | **Public link live.** Resume line exists; start applying | Run the same day twice; output identical | SQL: window functions. dbt incremental models |
| Nov 30 | Airflow replaces cron, with retries and a backfill DAG. Block inference, partial trips, schedule versioning, schema-drift detection, all tests, alerts, runbook. SLO tile. Baseline real-time detector as a 1-minute micro-batch (ADR-003) | One-command backfill works; SLOs reported daily; baseline detector precision measured | Load a day twice, drop a feed for 6 hours, swap in a new schedule mid-week | DDIA ch. 5 and 11. Kimball ch. 1 to 3 |
| Dec 15 | Swiftly into Redpanda: bronze archiver plus stateful ghost detector (ADR-003). LLM alert-cause extraction with eval, if alert text exists (ADR-002, decision 6). Fuzzy matching. Iceberg only if an ADR-002 decision 5 trigger is hit | ADR-003 acceptance criteria met; extractor passes its eval bar | Kill the consumer mid-batch; prove no duplicate or lost alerts. Replay 7 days through a new detector version and score it | DDIA ch. 10 and 11. Event time, watermarks, timers |
| Mid-Dec | Metro service change goes live (confirm the date) | Prior-month numbers unchanged; new trip IDs matched | The change itself | — |
| Jan 15 | December reconciliation against Metro's report. Cluster-bootstrap intervals over about 60 days. Equity analysis. Hand-validate 50 trips. Threshold sensitivity. Dataset release on S3 and Hugging Face. README, diagram, launch post. Pitch two advocacy groups or reporters | Three findings with method and validation; mock deep-dive interview passed cold | Destroy and rebuild the stack from Terraform in under 30 minutes (bronze bucket excluded by `prevent_destroy`) | Bootstrap methods. Questions you must answer cold, below |

**Order matters.** Early milestones use the simplest tools (cron, DuckDB) so you feel why Airflow and Redpanda exist before adopting them. Every new tool gets a decision record, and Iceberg arrives only on evidence.

**Agent-written code merges only after you explain it back** (ADR-002, decision 2). Answer the cold questions weekly, without notes.

**If time slips** (finals, work), cut in this order: shape projection, fuzzy matching, the equity analysis, then LLM extraction. If streaming is cut, the detector runs on its baseline. Never cut the Nov 30 milestone; reliability is what interviewers test, and never stop the poller.

## Definition of done and engineering standards

The project is done when a skeptical senior engineer could clone it, run it, and find nothing embarrassing.

- [ ] `make up` runs the whole stack locally from a fresh clone in under 10 minutes
- [ ] `make test` runs offline against recorded fixtures, with no API keys
- [ ] CI on every PR: lint (ruff), type check, unit tests, `dbt build` on fixture data
- [ ] All cloud resources defined in Terraform; nothing created by clicking in the console
- [ ] Secrets in environment variables or a secrets manager, never in the repo
- [ ] README answers, in order: what question, what finding, how it works (diagram), how to run it, known limitations
- [ ] A decision record (`docs/decisions/NNN-title.md`) for every significant choice: context, options, decision, consequences
- [ ] A runbook entry for every alert
- [ ] Monthly cloud cost measured and stated in the README
- [ ] Monthly totals reconciled with Metro's published report, with every large difference explained
- [ ] Public dataset released with a data dictionary and method notes
- [ ] Every number in the dashboard and README traceable to a query in the repo

**Working style.** One PR per meaningful change, with a description of what and why. You write the hard SQL and matching logic yourself; AI is fine for Terraform, Docker, and config boilerplate. Send each milestone PR for a staff-level review.

## Questions you must answer cold

Every answer lives in a section above. If you can't answer one without notes, that part of the system isn't really built yet.

1. What happens if the poller fetches the same snapshot twice, or a dbt run executes twice?
2. How do you tell a canceled trip from a feed outage, or from a bus running with a broken GPS unit?
3. Why partition by service date instead of arrival time? Where does a trip at 25:10 go?
4. Metro changed the schedule mid-month. How are last month's numbers still correct?
5. You fixed a bug in trip matching. How do you recompute six weeks of history, and how long does it take?
6. Why does the ghost detector need streaming, when a poller every 10 seconds is just as fast? What did the micro-batch baseline measure? And did you adopt Iceberg, and what problem made you (or didn't)?
7. The stream consumer crashes mid-batch. Do you get duplicates or loss? What does "exactly once" actually mean in your system?
8. Why is a Wilson interval wrong here, and what does the cluster bootstrap fix?
9. Your rate disagrees with Metro's monthly report by 3 points on one line. Walk me through debugging it.
10. This now has to cover 50 agencies. What breaks first, and what would you change?
11. LLM output isn't deterministic. How is the alert-cause job still idempotent, how do you know the extractor is accurate, and what does it cost per month?
12. Show me your worst incident. What was the root cause, and what did you change so it can't recur?

## Risks and open questions

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Missing cancellation history if the poller goes down, since the feed shows only current cancellations | Medium | Start archiving on day 2; external heartbeat; log every gap |
| Metro's beta API changes URLs or fields | Medium | Schema-drift detection; Swiftly as a second path |
| Trip IDs change at service changes | High | Versioned schedules; match against the version in force |
| Untracked buses inflate missed counts | High | Block inference, hand validation, stated as a limitation |
| Metro's monthly report counts something different from your metric | Medium | Find its definition before comparing; reconcile on matching scope |
| Streaming eats too much time | Medium | v1 runs on micro-batches; streaming is additive, not a rewrite; the baseline detector ships regardless (ADR-003) |
| Streaming doesn't beat the baseline | Medium | A legitimate result: record it in an ADR with the numbers (ADR-003) |
| Swiftly key arrives late | Medium | Request it by Nov 14; the baseline detector runs on the Metro API meanwhile |
| Airflow and Redpanda don't fit in 4 GB | Medium | Redpanda at 1 GB; measure; ask before a larger instance |
| Agent-written code the owner can't defend | Medium | Explain-back merge gate (ADR-002, decision 2) |
| LLM spend creeps up | Low | Content-hash cache, Batch API, Anthropic Console spend cap |
| Cloud bill creeps up | Low | Billing alarm at $40 in Terraform |
| Finals and work compress the schedule | High | Cut list in the plan |

**Open questions to settle by Nov 14:**

- The exact realtime endpoint URLs and formats live today, and whether the Metro API and Swiftly feeds match
- Whether canceled-service entries use the same trip IDs as GTFS static
- What Metro's monthly cancellation report counts, and whether past months are available
- The date of the next bus service change
- Whether Metro publishes service-alert text, and how many unique alerts appear per day (gates ADR-002, decision 6, and its cost)
- How long Swiftly takes to issue an API key (gates the Dec 15 streaming milestone)

**Sources:** [Metro API](https://api.metro.net) · [Metro API guide](https://lacmta.github.io/metro-api-v2/docs/intro) · [Metro developer page, mirrored](https://backiee.wasmer.app/https_developer_metro_net/api) · [Metro bus cancellation report](https://www.metro.net/riding/nextrip/) · [LA Metro bus GTFS](https://gitlab.com/LACMTA/gtfs_bus) · [Metro GTFS notes](https://lacmta.github.io/gtfs-bus) · [Mobility Database](https://mobilitydatabase.org/feeds/gtfs/mdb-29) · [Transitland archive](https://transit.land/feeds/f-9q5-metro~losangeles) · [Metro board report, Feb 2026](https://datamade-metro-pdf-merger.s3.amazonaws.com/2026-0066.pdf) · [TransitCenter on ghost buses](https://transitcenter.org/ghost-buses-are-haunting-riders-across-america/) · [King County ghost-bus legislation](https://kingcounty.gov/es-es/dept/council/governance-leadership/county-council/newsroom/2025/03-04-balducci-baron-perry-ghost-bus-passage-release)
