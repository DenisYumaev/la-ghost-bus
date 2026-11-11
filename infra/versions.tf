terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State in S3 with native locking (ADR-004, decision 4). Settings come from
  # the gitignored backend.hcl, so the account ID isn't committed:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
