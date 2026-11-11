"""Poller entry point. Placeholder until day 2.

Day 2 replaces the loop body with fetches of the Metro API feeds, content-hash
keyed writes to bronze, and the fetch log (ADR-001, decisions 1, 3, and 6).
For now it only proves the container builds, starts, and stops cleanly.
"""

import logging
import time

log = logging.getLogger("ingest.poller")


def run(iterations: int | None = None, interval_s: float = 30.0) -> int:
    """Log a heartbeat every `interval_s` seconds and return the number of ticks.

    `iterations=None` runs forever; tests pass a small number.
    """
    ticks = 0
    while iterations is None or ticks < iterations:
        log.info("poller placeholder tick %d", ticks)
        ticks += 1
        if iterations is None or ticks < iterations:
            time.sleep(interval_s)
    return ticks


def main() -> None:
    # Log timestamps in UTC, matching how every time is stored (hard rule 5).
    logging.Formatter.converter = time.gmtime
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)sZ %(levelname)s %(name)s %(message)s",
    )
    run()


if __name__ == "__main__":
    main()
