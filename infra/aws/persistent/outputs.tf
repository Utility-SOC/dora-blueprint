output "region" {
  value = var.region
}

output "state_bucket" {
  value = module.state_bucket.id
}

output "evidence_bucket" {
  value = module.evidence_bucket.id
}

output "backups_bucket" {
  value = module.backups_bucket.id
}

output "kms_key_arn" {
  description = "Can be added as a second SOPS recipient (`kms:` in .sops.yaml) alongside age."
  value       = aws_kms_key.platform.arn
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository variable for .github/workflows/cloud-lab.yaml."
  value       = one(aws_iam_role.github_deploy[*].arn)
}
