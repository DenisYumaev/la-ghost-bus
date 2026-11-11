# Start here

Do these in order. Steps 1 to 3 are yours; Claude Code does step 5 onward.

## 1. AWS account (you, ~15 minutes)

1. Sign up on the **Paid** plan. Credits are identical, and the account never auto-closes.
2. Turn on MFA for the root account. Then stop using root.
3. Billing → Budgets: create a $40 monthly budget with email alerts at 50%, 80%, and 100%.
4. Create an IAM Identity Center user (or an IAM user) for this project with admin access to start.
5. On your laptop: install the AWS CLI, run `aws configure` (or `aws configure sso`), then confirm `aws sts get-caller-identity` works.

Never give Claude Code root credentials.

## 2. Tools on your laptop

- Python 3.12 and [uv](https://docs.astral.sh/uv/)
- Docker Desktop
- Terraform
- Git and a GitHub account, with an empty repo named `la-ghost-bus`
- Claude Code

## 3. Run the day-1 probe (you, ~2 minutes)

```bash
python3 scripts/day1_probe.py
```

It writes raw responses to `fixtures/` and a summary to `fixtures/REPORT.md`. Read the report, fill in the checklist at the bottom of `docs/decisions/001-ingestion-decisions.md`, and bring anything surprising back to the planning chat before building on it.

## 4. Put this folder in place

Unzip this folder, rename it `la-ghost-bus`, and open a terminal in it. It already contains `CLAUDE.md`, `docs/`, and `scripts/`, which Claude Code reads automatically.

## 5. Paste this into Claude Code

```text
Read CLAUDE.md, docs/SPEC.md, and docs/decisions/001-ingestion-decisions.md first. Then set up the repo for day 1:

1. Repo: git init, Python 3.12 with uv, ruff, pytest, a .gitignore that excludes secrets, *.tfstate, .terraform/, .env, and fixtures larger than 1 MB, a README stub, and a Makefile with up, test, and lint targets.
2. Create the folder layout from CLAUDE.md. Move the probe's output in fixtures/ into tests/fixtures/ if it exists.
3. Docker: a Dockerfile and docker-compose.yml with a placeholder poller service. No Airflow or Redpanda yet.
4. CI: a GitHub Actions workflow running ruff and pytest on every PR.
5. Terraform in infra/: an S3 bucket for bronze data (versioning on, public access blocked, prevent_destroy), and an AWS Budget with an email alert at $40 a month. Local state for now. Use the AWS profile configured on this machine. Show me terraform plan and wait for my approval before apply.
6. Do not create IAM users, access keys, or EC2 instances.

Explain each choice briefly as you go. I want to understand and defend it.
```

## 6. Day 2

Once the repo is set up, the next session builds the poller and gets it archiving 24/7. That is the one deadline that matters: every day the poller isn't running is cancellation history lost for good.
