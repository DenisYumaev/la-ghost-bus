# Runbook

One entry per alert: what it means, how to check, how to recover.

## AWS budget alert ($40 a month)

- **Means:** actual or forecast monthly spend has reached $40.
- **Check:** Billing console → Cost Explorer, grouped by service, for the current month.
- **Recover:** find the resource behind the jump and fix or remove it in Terraform.
  Never delete anything in the bronze bucket.
