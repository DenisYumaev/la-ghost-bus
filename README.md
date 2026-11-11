# LA Ghost Bus Tracker

> Status: day 1. Repo scaffolding only; the poller starts archiving on day 2.

## The question

Of every bus trip LA Metro schedules, how many never run? And how much of that
is outside Metro's canceled-service feed, which lists only cancellations
announced in advance?

## Finding

_None yet._

## How it works

See [`docs/SPEC.md`](docs/SPEC.md) for the design and
[`docs/decisions/`](docs/decisions/) for the decision records. A diagram comes later.

## How to run

Requires Python 3.12, [uv](https://docs.astral.sh/uv/), Docker, and Terraform.

```bash
make install   # locked dev dependencies
make lint      # ruff, mypy, fixture size check
make test      # offline tests
make up        # local stack (placeholder poller for now)
make tf-check  # terraform fmt + validate, offline
```

## Known limitations

_To be written._

## License and data

Code is under the [MIT License](LICENSE). Transit data comes from LA Metro and
remains subject to LA Metro's terms (sources listed in
[`docs/SPEC.md`](docs/SPEC.md#data-sources)); credit LA Metro when using it. The terms for redistributing archived data are being
confirmed before any public dataset release.
