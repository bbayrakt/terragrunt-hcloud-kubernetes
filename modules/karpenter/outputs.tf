output "release_name" {
  description = "Karpenter Helm release name."
  value       = helm_release.karpenter.name
}

output "namespace" {
  description = "Kubernetes namespace the Karpenter provider controller is installed into."
  value       = helm_release.karpenter.namespace
}

output "nodeclass_name" {
  description = "Managed HCloudNodeClass name."
  value       = var.nodeclass_name
}

output "nodepool_name" {
  description = "Managed NodePool name."
  value       = var.nodepool_name
}
