.DEFAULT_GOAL := help
.PHONY: help install up down logs test lint fmt plan

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

install: ## Install locked dev dependencies into .venv
	uv sync --locked

up: ## Build and start the local stack
	docker compose up --build --detach

down: ## Stop the local stack
	docker compose down

logs: ## Follow logs from the local stack
	docker compose logs --follow

test: ## Run all tests offline
	uv run --locked pytest

lint: ## Ruff lint + format check, mypy, fixture size check
	uv run --locked ruff check .
	uv run --locked ruff format --check .
	uv run --locked mypy
	scripts/check_fixture_sizes.sh

fmt: ## Auto-fix lint issues and format
	uv run --locked ruff check --fix .
	uv run --locked ruff format .

# There is deliberately no `apply` target: apply is run by hand after the
# plan has been read and approved (CLAUDE.md hard rule 3).
plan: ## Terraform plan for infra/
	terraform -chdir=infra plan
