from ingest import poller


def test_run_stops_after_requested_iterations() -> None:
    assert poller.run(iterations=3, interval_s=0) == 3
