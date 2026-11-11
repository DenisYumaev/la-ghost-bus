## What changed

## Why

## How it was tested

## Relates to

<!-- ADR number(s), and the milestone in ADR-002 -->

## Checklist

- [ ] `make lint` and `make test` pass locally
- [ ] Nothing in bronze is modified or deleted (hard rule 1); every job is idempotent (hard rule 2)
- [ ] No secrets, `*.tfstate`, `*.tfvars`, or `.env` committed
- [ ] Terraform changes: `terraform plan` was shown and approved before apply
- [ ] Agent-written code: the owner explained it back (what it does, why this approach, what would break it). ADR-002, decision 2
