provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # Every resource gets these tags, so Cost Explorer can split spend by project.
  default_tags {
    tags = {
      Project   = "la-ghost-bus"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
