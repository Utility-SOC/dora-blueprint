output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "expires_at" {
  description = "When the reaper in .github/workflows/cloud-lab.yaml will destroy this cluster."
  value       = var.expires_at
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
