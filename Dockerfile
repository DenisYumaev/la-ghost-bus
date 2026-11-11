# syntax=docker/dockerfile:1
FROM python:3.12-slim

# Copy the uv binary from its official image, pinned to the version used locally.
COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Dependencies first, in their own layer: code edits don't trigger a reinstall.
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

COPY ingest/ ./ingest/

# Run as an unprivileged user; the poller needs no root access.
RUN useradd --system --uid 10001 --no-create-home app
USER app

CMD ["python", "-m", "ingest.poller"]
