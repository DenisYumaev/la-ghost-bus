# Incidents

One file per incident: `YYYY-MM-DD-short-slug.md`. Blameless: describe what the
system and process allowed, not who slipped. See ADR-002, decision 4.

**An incident is any of:** an SLO breach; a gap in bronze not explained by the
fetch log; any manual action on production data; a wrong number reaching the
public dashboard.

## Template

```markdown
# YYYY-MM-DD: <one-line summary>

- **Status:** open | resolved
- **Severity:** data lost | data delayed | wrong output | near miss
- **Impact:** <feeds affected, minutes of data lost or delayed, SLO budget used>
- **Detected by:** <alert name / heartbeat / dashboard / by hand>, <minutes after start>

## Timeline (UTC)

- HH:MM what happened
- HH:MM detected
- HH:MM mitigated
- HH:MM resolved

## Root cause

<the underlying cause, not just the trigger; ask "why" until it is fixable>

## What went well / what went badly

## Action items

- [ ] <change> (PR #)
```
