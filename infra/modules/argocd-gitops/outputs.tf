output "apps_project_name" {
  description = "Name of the `apps` AppProject"
  value       = argocd_project.apps.metadata[0].name
}

output "platform_project_name" {
  description = "Name of the `platform` AppProject"
  value       = argocd_project.platform.metadata[0].name
}

output "gitops_repository" {
  description = "Registered GitOps repository URL"
  value       = argocd_repository.gitops.repo
}
