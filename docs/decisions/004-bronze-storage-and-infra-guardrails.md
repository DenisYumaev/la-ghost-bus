# ADR-004: Bronze keys, compaction, storage cost model, and infrastructure guardrails

- **Status:** Accepted
- **Date:** 2026-11-10
- **Scope:** How bronze objects are keyed and deduplicated, where compacted data lives, how storage cost is modeled, and how "bronze is sacred" and Terraform state are enforced in AWS
- **Supersedes:** ADR-001 decision 6, but only its key format and duplicate check. Its partitioning by UTC fetch date and its fetch log stand.

## Context

ADR-001 decision 6 keys bronze objects as `<fetched_at_utc>_<sha256[:16]>.<ext>` and says a write is skipped "if a file with that hash already exists for the feed." Those two parts conflict:

- **Same bytes, different keys.** The fetch time is in the key, so the same bytes fetched twice get two different keys.
- **The check needs a lookup S3 can't do.** S3 can't find an object by a key *suffix* without listing the partition, and a list-then-write check is a race whenever two pollers overlap.

Three other gaps:

- **The spec says bronze is "compacted nightly"** without saying where the output goes, which reads as if bronze files are rewritten.
- **Storage volume is unmeasured.** Swiftly at 5 to 10 seconds could break the $30 a month target within months.
- **"Bronze is sacred" lives only in CLAUDE.md.** Nothing in AWS enforces it, and Terraform state sits on a single laptop.

## Decision 1: Content-addressed keys with an atomic conditional write

```text
s3://<bucket>/bronze/<feed>/dt=YYYY-MM-DD/<sha256[:16]>.<pb|json>
```

- **The key is the hash; the fetch time lives in the fetch log.** Each fetch log row records `fetched_at`, `content_hash`, `object_key`, and an outcome: `written`, `duplicate`, `http_error`, or `network_error`.
- **The write is `PutObject` with `If-None-Match: *`.** S3 rejects it with `412 Precondition Failed` if the key already exists. The poller records that as `duplicate`, which counts as success. Deduplication is atomic in S3 itself, so overlapping pollers and restarts are safe with no lookup and no race.
- **`dt` is still the UTC fetch date** (ADR-001 decision 6). The same bytes fetched on two different UTC days produce two objects. That's accepted: it's rare, and it keeps each day's partition self-contained for compaction.
- **A 16-hex-character (64-bit) prefix is enough.** At 10 million objects, the chance of any collision is about 3 in a million, and a collision would show up as a `duplicate` whose bytes differ, which the poller can detect.

**To verify on day 2:** conditional writes behave as described on this *versioned* bucket. The test uses a scratch `selftest/` prefix outside `bronze/`, so the deny-delete policy (decision 4) doesn't make the test objects permanent.

**Alternatives considered:**
- Keep the fetch time in the key and list before writing: a race, and a list call on every fetch.
- A DynamoDB table of seen hashes: another service, with its own consistency questions.
- Hash-only keys with no `dt`: no cheap way to read one day for compaction.

## Decision 2: Compaction writes to a separate derived prefix; originals are never touched

- **Output location.** Nightly compaction reads one UTC day of one feed and writes `derived/compacted/<feed>/dt=YYYY-MM-DD/part-0.parquet`. Columns: `content_hash`, `object_key`, `fetched_at` (from the fetch log), and `payload`, the exact bytes.
- **`derived/` is rebuildable.** A rerun overwrites the whole day, which is idempotent (hard rule 2). The prefix may be deleted and regenerated.
- **Compaction is by UTC fetch day, not service date.** Assigning a service date needs parsing, which belongs to silver (ADR-001 decisions 2 and 6). The spec's "one Parquet file per feed per service date" is corrected to per UTC day.
- **The small originals in `bronze/` are kept forever** and never moved to a colder storage class. Lifecycle transitions are charged per object. At about 90,000 small objects a day, the transition fees would exceed the storage saved. Deleting originals after compaction would need its own superseding ADR.

## Decision 3: A storage and cost model, filled in with measured sizes by Nov 21

Prices are AWS list prices in us-west-2 at the time of writing; confirm them in the pricing calculator.

| Quantity | Formula |
| --- | --- |
| Bronze bytes per day | Σ over feeds of (average snapshot bytes × unique snapshots per day) |
| S3 storage in month *m* | cumulative GB stored × $0.023 per GB-month. This grows every month, because bronze is never deleted |
| S3 writes | objects per month × $0.005 per 1,000 PUTs |
| Redpanda disk | min(retention days × stream bytes per day, `retention.bytes` cap) × $0.08 per GB-month (gp3) |

**Planned defaults until measured:**
- **Swiftly snapshots are archived at most every 30 seconds**, while the stream keeps every message for 7 days. The Metro API, not Swiftly, is the source of record for the headline metric, so its archive fidelity is what matters.
- **Redpanda retention is capped by size as well as time.**

**Decision rule:** if the model projects month-6 AWS cost above the $30 target, cut cost in this order: Swiftly's archive rate, then Redpanda retention, then the VM size. Never cut Metro API archiving.

## Decision 4: Guardrails enforced in AWS

1. **Deny deletes on `bronze/*` in the bucket policy**, for every principal: `s3:DeleteObject` and `s3:DeleteObjectVersion`. Code bugs and mistyped commands can't remove raw data, and versioning keeps any overwritten bytes. This guards against accidents, not against an administrator, who can edit the policy. That edit would be a deliberate act, visible in CloudTrail and in a Terraform diff.
2. **The VM, on day 2, uses an instance role, not keys.** The role can only `PutObject` and `GetObject` on `bronze/*`, list the bucket, and do the same on `derived/*`. It has no delete on bronze. Access is through SSM Session Manager: no SSH key and no inbound security-group rules. A role attached to an instance isn't an IAM user and has no long-lived access keys (CLAUDE.md hard rule 4).
3. **Terraform state lives in S3 with native locking.**
   - A separate `infra/bootstrap` configuration creates the state bucket: versioned, public access blocked, TLS-only, with `prevent_destroy`. Bootstrap keeps its own tiny local state. If that state is lost, the bucket can be re-imported, and the bucket itself is protected.
   - The main configuration uses the S3 backend with `use_lockfile = true` (Terraform 1.10 and later; no DynamoDB table).
   - The backend settings come from a gitignored `infra/backend.hcl`, so the account ID isn't committed to the public repo.

**Alternatives considered:**
- S3 Object Lock in governance mode: stronger, but it complicates the scratch `selftest/` prefix and recovery, and the bucket policy covers the realistic failures.
- Keeping local state: one lost laptop means Terraform forgets the bronze bucket.
- HCP Terraform: another account and vendor for one developer.

## Consequences

- **Day 2 poller:**
  - Writes with `If-None-Match: *` and treats `412` as `duplicate`.
  - The fetch log gains `content_hash`, `object_key`, and `outcome`.
  - Verifies conditional-write behavior on the `selftest/` prefix first.
- **Day 2 VM Terraform** adds the instance role, the instance profile, the SSM policy, and a security group with no inbound rules. As always, the plan is shown first.
- **`terraform init` needs `-backend-config=backend.hcl`.** `make tf-check` stays offline with `-backend=false`.
- **The spec's compaction sentence and fetch-log columns** are updated to match this ADR.
