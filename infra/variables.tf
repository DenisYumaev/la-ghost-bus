variable "aws_region" {
  description = "Region for the bronze bucket. us-west-2 is close to LA and cheap."
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "Named profile from ~/.aws/config. No credentials ever live in this repo."
  type        = string
  default     = "default"
}

variable "budget_alert_email" {
  description = "Where budget alerts go. Set in terraform.tfvars (gitignored)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be an email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD (SPEC: billing alarm at $40)."
  type        = number
  default     = 40
}
