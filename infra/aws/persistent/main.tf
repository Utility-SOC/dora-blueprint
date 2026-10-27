# The part of the cloud lab that outlives every cluster: Terraform state for the ephemeral
# cluster stack, the evidence bucket (write-once), the backup bucket, and the cost guardrail.
# Applied once per AWS account (`make cloud-persistent`), never by the up/down cycle -- evidence
# and backups that disappear with the cluster they describe aren't evidence or backups.

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global; the account id keeps them unique without a random suffix.
  bucket_prefix = "${var.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_kms_key" "platform" {
  description         = "${var.name_prefix}: evidence/backup bucket encryption, and an optional SOPS recipient"
  enable_key_rotation = true
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.platform.key_id
}

# ---- Buckets (modules/bucket applies the shared baseline to each) ---------------------------

# Terraform state for infra/aws/cluster.
module "state_bucket" {
  source      = "./modules/bucket"
  name        = "${local.bucket_prefix}-tfstate"
  kms_key_arn = aws_kms_key.platform.arn
}

# Evidence: write-once (build-spec P7; README Phase 20's "MinIO object-lock remains a possible
# second mechanism" -- S3 Object Lock is that mechanism, managed).
module "evidence_bucket" {
  source      = "./modules/bucket"
  name        = "${local.bucket_prefix}-evidence"
  kms_key_arn = aws_kms_key.platform.arn
  object_lock = { mode = var.evidence_lock_mode, days = var.evidence_retention_days }
}

# Velero backups: outside every cluster, so a restore drill can target a brand-new one.
module "backups_bucket" {
  source      = "./modules/bucket"
  name        = "${local.bucket_prefix}-backups"
  kms_key_arn = aws_kms_key.platform.arn
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = module.backups_bucket.id

  rule {
    id     = "expire-superseded-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---- Cost guardrail ---------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_monthly_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# ---- Optional: GitHub Actions deploy role (OIDC, no long-lived keys) ---------------------------
#
# Risk acceptance, stated rather than hidden (build-spec P2): standing up EKS creates IAM roles,
# so this role gets AdministratorAccess. Compensating controls: only jobs running in the repo's
# `cloud-lab` GitHub environment can assume it (restrict that environment to the default branch;
# a required-reviewer rule would also hold the hourly reaper, so it's a trade-off, not a free
# extra), sessions last an hour, and a lab should live in its own AWS account -- never one
# holding anything else.

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.github_repository == "" ? 0 : 1
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_deploy" {
  count                = var.github_repository == "" ? 0 : 1
  name                 = "${var.name_prefix}-github-deploy"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:cloud-lab"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "github_deploy_admin" {
  count      = var.github_repository == "" ? 0 : 1
  role       = aws_iam_role.github_deploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
