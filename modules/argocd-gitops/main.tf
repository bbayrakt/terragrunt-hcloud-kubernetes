## AppProjects: apps (restricted) and platform (privileged)
##
## apps: cluster-scoped resources are default-deny in ArgoCD (empty cluster_resource_whitelist
## already blocks them); cluster_resource_blacklist is added anyway for defense-in-depth /
## self-documentation. namespace_resource_blacklist additionally blocks Role/RoleBinding, which
## are namespaced (default-allow) and would otherwise let an apps-tier app bind its ServiceAccount
## to a pre-existing ClusterRole and escalate within its own namespace.
## managed_namespace_metadata applies Pod Security Standard enforcement to any namespace this
## project creates via CreateNamespace=true, closing the gap that resource-kind whitelisting alone
## can't cover (privileged/hostPath/hostNetwork Pod specs).
resource "argocd_project" "apps" {
  metadata {
    name = "apps"
  }

  spec {
    description  = "Low-trust tier: ordinary apps, no cluster-scoped resource creation rights"
    source_repos = [var.gitops_repo_url]

    dynamic "destination" {
      for_each = var.apps_destination_namespaces
      content {
        server    = "https://kubernetes.default.svc"
        namespace = destination.value
      }
    }

    cluster_resource_blacklist {
      group = "*"
      kind  = "*"
    }

    namespace_resource_blacklist {
      group = "rbac.authorization.k8s.io"
      kind  = "Role"
    }

    namespace_resource_blacklist {
      group = "rbac.authorization.k8s.io"
      kind  = "RoleBinding"
    }
  }
}

## platform: explicit whitelist of the specific cluster-scoped kinds known platform-tier apps
## need (CRDs, ClusterRole/ClusterRoleBinding for the runner controller and Sealed Secrets).
## Extend platform_cluster_resource_whitelist, not this resource, when a future platform app
## needs a kind not already covered.
resource "argocd_project" "platform" {
  metadata {
    name = "platform"
  }

  spec {
    description  = "Privileged tier: apps that genuinely need cluster-scoped install rights"
    source_repos = [var.gitops_repo_url]

    dynamic "destination" {
      for_each = var.platform_destination_namespaces
      content {
        server    = "https://kubernetes.default.svc"
        namespace = destination.value
      }
    }

    dynamic "cluster_resource_whitelist" {
      for_each = var.platform_cluster_resource_whitelist
      content {
        group = cluster_resource_whitelist.value.group
        kind  = cluster_resource_whitelist.value.kind
      }
    }
  }
}

## ApplicationSets: one git directory generator per tier, hard-coded (non-templated) project
## per upstream ApplicationSet Security guidance -- a directory added under apps/* can never
## land in the platform project, since project assignment isn't a function of directory content.
## Application names are tier-prefixed to avoid a future apps/foo vs platform/foo name collision
## (Application objects share one namespace). syncPolicy.automated + preserveResourcesOnDeletion
## give "commit -> app appears" automatically while preventing an accidental directory deletion
## from cascade-deleting live resources now that Terraform's prevent_destroy safety net has been
## handed off to ArgoCD for these charts.
resource "argocd_application_set" "apps" {
  # Found via live apply: ArgoCD's API validates an ApplicationSet's referenced project at
  # creation time; without this, Terraform's default parallel resource creation can attempt to
  # create the ApplicationSet before the argocd_project transaction is visible, failing with
  # "ApplicationSet references project apps which does not exist".
  depends_on = [argocd_project.apps]

  metadata {
    name = "apps"
  }

  spec {
    generator {
      git {
        repo_url = var.gitops_repo_url
        revision = "HEAD"

        directory {
          path = "apps/*"
        }
      }
    }

    # Guards against an accidental directory deletion/rename in the GitOps repo cascade-deleting
    # live cluster resources -- Terraform's prevent_destroy safety net was deliberately removed
    # from these charts' CRDs/releases to hand ownership to ArgoCD; this keeps that hand-off from
    # also meaning "one fat-fingered `git rm -r` deletes everything".
    sync_policy {
      preserve_resources_on_deletion = true
    }

    template {
      metadata {
        name = "apps-{{path.basename}}"
      }

      spec {
        project = "apps"

        source {
          repo_url        = var.gitops_repo_url
          target_revision = "HEAD"
          path            = "{{path}}"
        }

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{path.basename}}"
        }

        sync_policy {
          automated {
            prune       = true
            self_heal   = true
            allow_empty = false
          }

          # Applies Pod Security Standard enforcement to the namespace this Application creates
          # via CreateNamespace=true -- closes the gap that AppProject resource-kind whitelisting
          # alone can't reach (a namespaced Pod/Deployment requesting privileged/hostPath/hostNetwork).
          managed_namespace_metadata {
            labels = {
              "pod-security.kubernetes.io/enforce" = var.apps_pod_security_level
            }
          }

          sync_options = [
            "CreateNamespace=true",
          ]
        }
      }
    }
  }
}

resource "argocd_application_set" "platform" {
  depends_on = [argocd_project.platform]

  metadata {
    name = "platform"
  }

  spec {
    generator {
      git {
        repo_url = var.gitops_repo_url
        revision = "HEAD"

        directory {
          path = "platform/*"
        }
      }
    }

    sync_policy {
      preserve_resources_on_deletion = true
    }

    template {
      metadata {
        name = "platform-{{path.basename}}"
      }

      spec {
        project = "platform"

        source {
          repo_url        = var.gitops_repo_url
          target_revision = "HEAD"
          path            = "{{path}}"
        }

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{path.basename}}"
        }

        sync_policy {
          automated {
            prune       = true
            self_heal   = true
            allow_empty = false
          }

          sync_options = [
            "CreateNamespace=true",
          ]
        }
      }
    }
  }
}

## GitOps repository registration -- read-only SSH deploy key, credential sourced from
## secrets.yaml the same way every other secret in this repo already is.
resource "argocd_repository" "gitops" {
  repo            = var.gitops_repo_url
  username        = "git"
  ssh_private_key = var.gitops_repo_ssh_private_key
}
