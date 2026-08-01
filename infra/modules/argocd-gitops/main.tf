## AppProjects: apps (restricted) and platform (privileged)
##
## apps: cluster-scoped resources are default-deny in ArgoCD (empty cluster_resource_whitelist
## already blocks them). The sole exception is Namespace: CreateNamespace=true's PreSync
## namespace-creation task is itself a cluster-scoped op, found blocked in live testing (U5/U7)
## by the wildcard cluster_resource_blacklist this project used to carry -- a blacklist entry
## re-excludes anything the whitelist explicitly allows, so a blanket `*/*` blacklist and a
## narrow whitelist exception are mutually exclusive, not layered defense-in-depth. Whitelisting
## only Namespace, with no blacklist at all, is safe: an Application's destination.namespace is
## already validated against apps_destination_namespaces at the AppProject level, so this can
## only ever create one of those pre-approved namespaces, never an arbitrary one. Everything else
## cluster-scoped remains denied by the empty-whitelist default. namespace_resource_blacklist
## additionally blocks Role/RoleBinding, which are namespaced (default-allow) and would otherwise
## let an apps-tier app bind its ServiceAccount to a pre-existing ClusterRole and escalate within
## its own namespace. managed_namespace_metadata applies Pod Security Standard enforcement to any
## namespace this project creates via CreateNamespace=true, closing the gap that resource-kind
## whitelisting alone can't cover (privileged/hostPath/hostNetwork Pod specs).
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

    cluster_resource_whitelist {
      group = ""
      kind  = "Namespace"
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
  # Also depends on argocd_repository (found by ce-code-review): the generator's repo_url must
  # already be registered, or the same class of "references X which does not exist" race applies
  # to the repository instead of the project.
  depends_on = [argocd_project.apps, argocd_repository.gitops]

  metadata {
    name = "apps"
  }

  spec {
    generator {
      git {
        repo_url = var.gitops_repo_url
        revision = "HEAD"

        directory {
          path = "${var.gitops_apps_path}/*"
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
  depends_on = [argocd_project.platform, argocd_repository.gitops]

  metadata {
    name = "platform"
  }

  spec {
    generator {
      git {
        repo_url = var.gitops_repo_url
        revision = "HEAD"

        directory {
          path = "${var.gitops_platform_path}/*"
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

          # ServerSideApply=true (found via live U6 testing): the gha-runner-scale-set-controller
          # chart's CRDs (autoscalinglisteners.actions.github.com etc.) are large enough that
          # client-side apply's kubectl.kubernetes.io/last-applied-configuration annotation
          # exceeds Kubernetes' 262144-byte annotation limit, failing every sync attempt with
          # "metadata.annotations: Too long". Server-side apply never writes that annotation, so
          # it isn't subject to the limit -- a known issue with this chart's CRDs specifically,
          # not a platform-tier-wide requirement, but scoped here since platform is the tier where
          # CRD-installing apps live by design (R7).
          sync_options = [
            "CreateNamespace=true",
            "ServerSideApply=true",
          ]
        }
      }
    }
  }
}

## GitOps repository registration -- supports three auth modes, selected by which variables are
## set: SSH deploy key (gitops_repo_ssh_private_key; username is hardcoded to "git" per SSH
## convention, regardless of gitops_repo_username), HTTPS credential auth (gitops_repo_username +
## gitops_repo_password, e.g. a personal access token), or no credentials at all for a public
## HTTPS repository (all three left null/default). Credential sourced from secrets.yaml the same
## way every other secret in this repo already is.
##
## local.using_ssh_auth is the single source of truth for which mode is active -- treats an
## empty string the same as null so a blanked-out (not unset) ssh key doesn't accidentally select
## SSH mode with an empty credential. The two preconditions below (found via code review: multiple
## independent reviewers converged on the same gap) reject ambiguous configurations at plan time
## instead of silently discarding one credential set or applying a malformed partial one.
locals {
  using_ssh_auth = var.gitops_repo_ssh_private_key != null && var.gitops_repo_ssh_private_key != ""
}

resource "argocd_repository" "gitops" {
  repo            = var.gitops_repo_url
  username        = local.using_ssh_auth ? "git" : var.gitops_repo_username
  password        = local.using_ssh_auth ? null : var.gitops_repo_password
  ssh_private_key = local.using_ssh_auth ? var.gitops_repo_ssh_private_key : null

  lifecycle {
    precondition {
      condition     = !(local.using_ssh_auth && (var.gitops_repo_username != null || var.gitops_repo_password != null))
      error_message = "Set either gitops_repo_ssh_private_key (SSH auth) or gitops_repo_username/gitops_repo_password (HTTPS auth), not both -- SSH would silently take precedence and the HTTPS credentials would be discarded."
    }
    precondition {
      condition     = (var.gitops_repo_username == null) == (var.gitops_repo_password == null)
      error_message = "gitops_repo_username and gitops_repo_password must both be set or both be null -- a lone username or password produces an incomplete HTTPS credential."
    }
    precondition {
      condition     = var.gitops_apps_path != var.gitops_platform_path
      error_message = "gitops_apps_path and gitops_platform_path must not be equal -- an overlapping path would let the same content land in both the restricted apps AppProject and the privileged platform AppProject, defeating the two-tier trust boundary."
    }
  }
}
