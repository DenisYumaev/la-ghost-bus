# ADR-003: Streaming exists to run a real-time ghost-bus detector

- **Status:** Accepted
- **Date:** 2026-11-10
- **Scope:** Why the project has a streaming path, what it must achieve, and how it is judged
- **Relates to:** ADR-001 decision 1 (Swiftly added as the streaming source). Supersedes the spec's plan to stream Swiftly into Redpanda and Iceberg without a stated requirement. Does not change any ADR-001 decision.

## Context

The original spec adds Swiftly, Redpanda, and an Iceberg-writing consumer in week 4, but names nothing they do that the batch path can't. The headline metric (missed trips per service day) is computed after a service day closes, so its latency doesn't matter. Streaming added only to put Kafka on a resume is easy for an interviewer to spot: "why stream?" needs an answer other than "to learn it."

So streaming gets one job with a real latency requirement, a cheaper baseline it must beat, measurable acceptance criteria, and a defined outcome if it doesn't earn its place.

## Decision

### The product: "likely missing right now"

A trip is flagged **likely missing** when its scheduled start plus a grace period (initially 10 minutes) passes with no vehicle observed on it. If a vehicle appears later, the flag is **retracted**. Flags are shown on the dashboard as a live list and published as a feed (Discord or RSS) that riders and advocates can follow.

This is the first public signal of a ghost bus while it's still affecting riders. Today that signal doesn't exist anywhere, because canceled trips produce no GPS data.

### Why this needs streaming, stated honestly

Latency alone does **not** justify a log. A poller hitting Swiftly every 10 seconds could also flag trips quickly. Four requirements together do:

| Requirement | Why batch is a poor fit |
| --- | --- |
| **R1. Detecting an absence needs timers.** A flag must fire at the deadline even when *no event arrives*. | Batch jobs react to data they read; an absence produces no data. A stateful consumer with event-time timers and a watermark expresses "nothing happened by T" directly. This is the core streaming problem in the project. |
| **R2. Event time, not arrival time.** Vehicle timestamps lag and arrive out of order. | The detector keys on vehicle timestamps, with a watermark (initially 2 minutes) for late events. Late events that clear a flag produce a retraction, not a silent overwrite. |
| **R3. Replay for backtesting.** Changing the grace period or matching rule must be testable against real history before it goes live. | Redpanda retains 7 days. A new detector version replays that window and is scored against final outcomes (below). Re-running against a poller isn't possible, because a poller has no history. |
| **R4. One ingest, several consumers.** Swiftly is polled once (one API key, one rate limit). | The topic feeds the bronze archiver, the detector, and live metrics independently. Each can crash, restart, or be replaced without touching the others, or the ingest. |

### Baseline first

Before Redpanda exists, a **baseline detector** runs as a 1-minute micro-batch job over the Metro API snapshots already being archived. It implements the same rule. Its job is to set the bar: streaming is adopted because it beats a measured baseline, not because the spec says so.

The baseline ships regardless. If streaming is ever cut, the product survives on the baseline.

### Design

```text
Swiftly (5-10 s) ─► poller ─► Redpanda topic: vehicle_positions (7-day retention)
                                   │
                ┌──────────────────┼────────────────────┐
                ▼                  ▼                    ▼
         bronze archiver     ghost detector        live metrics
         (S3, ADR-001 d6)    state: today's trips
                             (from dim_schedule_trips)
                             timers at start + grace
                                   │
                                   ▼
                     fct_ghost_alerts (flag / retract events)
                                   │
                                   ▼
                  dashboard live list · public feed · nightly scoring
```

- **The expected side comes from batch.** Today's trips come from `dim_schedule_trips`, loaded at service-day start and refreshed when the schedule version changes. The stream supplies only what was observed. Joining a stream to a table is the pattern used in production streaming systems.
- **Trips are matched through the crosswalk** (ADR-001 decision 4), never on raw `trip_id`.
- **Delivery is effectively once:** at-least-once delivery plus an idempotent sink. The consumer commits offsets only after the sink write. Alert rows are keyed on `(trip_id, service_date, detector_version, event_type)`, so a replayed or duplicated write is a no-op.
- **State is derived, the log is the source of truth.** On restart the detector rebuilds state by replaying from the start of the service day. There's no separate state store to back up or corrupt.
- **The bronze archiver writes raw Swiftly responses** using ADR-001 decision 6's layout and hashing. Redpanda is a buffer, never the archive: bronze stays on S3, append-only.
- **Single node, one partition per topic.** Volume is a few hundred messages a second at most, and one partition keeps ordering trivial. The scale path (partition by route, consumer group per partition) is written down, not built.
- **The consumer is plain Python, not Flink.** Flink would run a JVM on a 4 GB VM shared with Airflow, which doesn't fit, and the state here is small enough to hold in memory.

### How it's judged

Every flag is scored once its service day is finalized in `fct_trip_outcomes`:

- **Precision:** the share of flags whose trip ended `missed` or `unknown`, rather than `ran` or `partial`.
- **Recall:** the share of missed trips flagged within 15 minutes of their scheduled start.
- **Detection latency:** the time from the deadline (start + grace) to when the flag was emitted.
- **Retraction rate:** the share of flags later withdrawn.

These are published on the dashboard per detector version.

**Acceptance criteria (all required before streaming counts as done):**

1. p95 detection latency of 30 seconds or less, against the baseline's measured value
2. Precision of at least 0.8 at the chosen grace period, measured over 7 or more service days
3. Killing the consumer mid-batch causes no duplicate or lost alerts; this is the chaos drill
4. A 7-day replay through a new detector version is scored end to end
5. 72 hours stable alongside the batch path, with both agreeing on daily outcomes

**If streaming doesn't earn its place**, meaning the baseline meets the latency and precision bars and replay is never used, a new ADR records that streaming was evaluated and not adopted, with the numbers. That's a legitimate engineering result and a stronger interview story than adopting a tool by default.

## Alternatives considered

- **Stream Swiftly into Iceberg as the spec planned:** no requirement it serves; Iceberg's case is made separately (ADR-002, decision 5).
- **Detector as a cron job only:** this is the baseline. It can't backtest, and every new consumer means another poller.
- **Flink or Spark Structured Streaming:** proper event-time support, but too heavy for one small VM and one developer. Named in the scale-up path.
- **Kafka instead of Redpanda:** same API but heavier to run (ZooKeeper or KRaft tuning, and the JVM). The spec's original reasoning still holds.

## Consequences

- **Request a Swiftly API key this week.** ADR-001 notes approval may take days, and the streaming milestone is Dec 15.
- **Memory is tight.** Redpanda runs with `--smp 1 --memory 1G`. Measure Airflow, Redpanda, and the poller together on the VM; if they don't fit in 4 GB, ask before moving to a larger instance (CLAUDE.md hard rule 3).
- **New gold table:** `fct_ghost_alerts`, plus a nightly scoring model and a dashboard tile.
- **The dashboard gains a live element,** which gives the public link a reason to be visited more than once.
- **Interview questions 6 and 7 in the spec now have concrete answers:** why stream (R1 to R4) and what "exactly once" means here (at-least-once plus an idempotent sink).
