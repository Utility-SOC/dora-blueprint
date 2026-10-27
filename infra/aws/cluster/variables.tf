variable "region" {
  description = "Must match infra/aws/persistent's region (the backup bucket lives there)."
  type        = string
  default     = "eu-west-1"
}

variable "name_prefix" {
  description = "Must match infra/aws/persistent's name_prefix."
  type        = string
  default     = "dora-blueprint"
}

variable "name" {
  description = "Cluster name. Distinct names allow several labs at once (e.g. one per trainee)."
  type        = string
  default     = "dora-lab"
}

variable "backups_bucket" {
  description = "From infra/aws/persistent's `backups_bucket` output (make cloud-up passes it)."
  type        = string
}

variable "kms_key_arn" {
  description = "From infra/aws/persistent's `kms_key_arn` output -- the backup bucket's encryption key."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS minor version. 1.36 matches the Talos tier's pin (bootstrap/install.sh)."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Worker instance type. m7i.xlarge (4 vCPU / 16 GiB) x3 fits the full tier with room to lose a node."
  type        = string
  default     = "m7i.xlarge"
}

variable "node_count" {
  description = "Worker count. 3 is the minimum where a node-kill drill still leaves two to reschedule onto."
  type        = number
  default     = 3
}

variable "capacity_type" {
  description = "ON_DEMAND, or SPOT for roughly half the worker cost (nodes can then disappear on their own -- an unplanned drill)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway instead of one per AZ: cheaper, but egress depends on one AZ. Fine for a lab, flagged for anything else."
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint. No default on purpose -- an API open to 0.0.0.0/0 should be a decision someone typed."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "IAM principals (besides whoever runs apply) granted cluster-admin -- e.g. your own user/SSO role when CI creates the cluster."
  type        = list(string)
  default     = []
}

variable "expires_at" {
  description = "RFC 3339 UTC time this lab is due for teardown, stamped on every resource as `expires-at`. `make cloud-up TTL_HOURS=4` computes it; .github/workflows/cloud-lab.yaml's hourly reaper destroys anything past it. Re-applying with a later value is how you extend a lab -- deliberately, not as a side effect of any apply."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", var.expires_at))
    error_message = "expires_at must look like 2026-10-27T18:00:00Z."
  }
}
