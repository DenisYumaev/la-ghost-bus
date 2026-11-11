"""Day 1 probe for the LA Ghost Bus Tracker.

Hits every data source once, saves raw responses as test fixtures,
and answers the spec's open questions. Standard library only.

Run:  python3 scripts/day1_probe.py   (from any directory)
Output: tests/fixtures/ (raw responses) and tests/fixtures/REPORT.md
"""

import csv
import io
import json
import time
import urllib.request
import zipfile
from datetime import UTC, datetime
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures"
OUT.mkdir(parents=True, exist_ok=True)
API = "https://api.metro.net"
GTFS_URL = "https://gitlab.com/LACMTA/gtfs_bus/raw/master/gtfs_bus.zip"
report: list[str] = [f"# Day 1 probe report\n\nRun at {datetime.now(UTC).isoformat()}\n"]


def fetch(url: str) -> tuple[int, bytes, float]:
    """Return (status, body, seconds). Never raises."""
    start = time.time()
    req = urllib.request.Request(url, headers={"User-Agent": "ghost-bus-probe/0.1"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read(), time.time() - start
    except urllib.error.HTTPError as e:
        return e.code, e.read(), time.time() - start
    except Exception as e:  # network errors, timeouts
        return 0, str(e).encode(), time.time() - start


def save(name: str, body: bytes) -> Path:
    path = OUT / name
    path.write_bytes(body)
    return path


def note(line: str = "") -> None:
    print(line)
    report.append(line)


# 1. Discover the API's real endpoint list instead of guessing.
note("## 1. Metro API endpoints\n")
status, body, secs = fetch(f"{API}/openapi.json")
paths: list[str] = []
if status == 200:
    save("openapi.json", body)
    paths = sorted(json.loads(body).get("paths", {}))
    note(f"openapi.json: {len(paths)} paths found ({secs:.1f}s)\n")
    for p in paths:
        note(f"- `{p}`")
else:
    note(
        f"openapi.json failed: HTTP {status}. Open {API}/docs in a browser and list paths by hand."
    )

# 2. Hit every GET path that needs no unknown parameter, plus agency-scoped ones.
note("\n## 2. Responses\n")
note("| Path | HTTP | Bytes | Seconds | Saved as |")
note("| --- | --- | --- | --- | --- |")
candidates = [p for p in paths if "{" not in p]
candidates += [
    p.replace("{agency_id}", "LACMTA") for p in paths if p.count("{") == 1 and "{agency_id}" in p
]
for p in candidates:
    status, body, secs = fetch(API + p)
    fname = "api_" + p.strip("/").replace("/", "__").replace("{", "").replace("}", "") + ".bin"
    if status == 200:
        save(fname, body)
    note(f"| `{p}` | {status} | {len(body):,} | {secs:.1f} | {fname if status == 200 else '-'} |")

# 3. GTFS static schedule.
note("\n## 3. GTFS static\n")
status, body, secs = fetch(GTFS_URL)
trip_ids: set[str] = set()
if status == 200:
    save("gtfs_bus.zip", body)
    with zipfile.ZipFile(io.BytesIO(body)) as z:
        note(f"Downloaded {len(body) / 1e6:.1f} MB, files: {', '.join(sorted(z.namelist()))}\n")
        with z.open("trips.txt") as f:
            rows = list(csv.DictReader(io.TextIOWrapper(f, "utf-8-sig")))
        trip_ids = {r["trip_id"] for r in rows}
        note(f"trips.txt: {len(rows):,} trips, columns: {', '.join(rows[0].keys())}")
        note(f"Sample trip_ids: {', '.join(list(trip_ids)[:3])}")
        if "feed_info.txt" in z.namelist():
            with z.open("feed_info.txt") as f:
                note(f"feed_info.txt: {f.read().decode('utf-8-sig').strip()}")
else:
    note(f"GTFS download failed: HTTP {status}")

# 4. Open question: do canceled-service trip IDs match GTFS trip_ids?
note("\n## 4. Do canceled-service trip IDs match GTFS?\n")
cancel_file = next(OUT.glob("api_canceled_service__all*.bin"), None)
if cancel_file and trip_ids:
    data = json.loads(cancel_file.read_bytes())
    items = data if isinstance(data, list) else data.get("canceled_data", data.get("data", []))
    if isinstance(items, dict):
        items = list(items.values())
    note(f"Canceled entries: {len(items)}")
    if items:
        note(f"Fields on first entry: {', '.join(items[0].keys())}")
        id_fields = [k for k in items[0] if "trip" in k.lower()]
        for k in id_fields:
            vals = {str(i.get(k)) for i in items if i.get(k)}
            hits = len(vals & trip_ids)
            note(
                f"- `{k}`: {hits} of {len(vals)} values match a GTFS trip_id. "
                f"Sample: {list(vals)[:2]}"
            )
        if not id_fields:
            note("No field with 'trip' in its name. Inspect the fixture by hand.")
else:
    note("Skipped: need both the canceled-service response and GTFS trips.")

# 5. Is the realtime feed protobuf or JSON, and how fresh?
note("\n## 5. Realtime feed format\n")
for f in sorted(OUT.glob("api_*vehicle*")) + sorted(OUT.glob("api_*trip_update*")):
    head = f.read_bytes()[:200]
    kind = "JSON" if head.lstrip()[:1] in (b"{", b"[") else "binary (likely protobuf)"
    note(f"- {f.name}: {kind}, {f.stat().st_size:,} bytes")

(OUT / "REPORT.md").write_text("\n".join(report))
print(f"\nDone. Fixtures and REPORT.md are in {OUT.resolve()}")
