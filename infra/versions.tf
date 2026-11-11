terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state for now (terraform.tfstate, gitignored). Moving to an S3
  # backend with native locking is a later step and gets its own ADR.
}
