variable "region" {
  description = "Home region. eu-west-1 by default -- this platform's example tenant is an EU payment institution (docs/00-scope.md)."
  type        = string
  default     = "eu-west-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name; also the `project` tag the cluster reaper filters on."
  type        = string
  default     = "dora-blueprint"
}

variable "budget_monthly_usd" {
  description = "Monthly AWS budget for the whole account. Alerts at 80% actual and 100% forecast spend."
  type        = number
  default     = 50
}

variable "budget_alert_email" {
  description = "Where budget alerts go. Required: a forgotten cluster is the single biggest cost risk here."
  type        = string
}

variable "evidence_retention_days" {
  description = "Default Object Lock retention on the evidence bucket. Objects can't be overwritten or deleted for this long."
  type        = number
  default     = 365
}

variable "evidence_lock_mode" {
  description = "GOVERNANCE (an account admin can still override, with an explicit bypass permission) or COMPLIANCE (nobody can, not even root, until retention expires). GOVERNANCE by default so a lab account can still be cleaned up."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.evidence_lock_mode)
    error_message = "evidence_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "github_repository" {
  description = "owner/repo allowed to run .github/workflows/cloud-lab.yaml against this account via OIDC (no stored keys). Empty disables the role."
  type        = string
  default     = ""
}
