locals {
  worker_machineconfig_secret_name = "karpenter-worker-machineconfig"
  image_selector = {
    os                 = "talos"
    cluster            = var.cluster_name
    talos_version      = var.talos_version
    talos_schematic_id = data.hcloud_image.cluster_talos.labels["talos_schematic_id"]
  }

  controller_values = merge(
    {
      clusterName = var.cluster_name
      replicas    = 1
      auth = {
        secretRef = {
          name = var.hcloud_token_secret_name
          key  = "token"
        }
      }
    },
    var.controller_values,
  )
}

resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "hcloud_token" {
  metadata {
    name      = var.hcloud_token_secret_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    token = var.hcloud_token
  }

  depends_on = [kubernetes_namespace_v1.this]
}

data "hcloud_network" "cluster" {
  name = var.network_name
}

data "hcloud_image" "cluster_talos" {
  with_selector     = "os=talos,cluster=${var.cluster_name},talos_version=${var.talos_version}"
  with_architecture = "x86"
  most_recent       = true
}

# Render the Karpenter chart's CRDs via data.helm_template and apply
# them with kubernetes_manifest instead .
data "helm_template" "karpenter_crds" {
  name         = var.release_name
  namespace    = var.namespace
  repository   = var.helm_repository
  chart        = var.helm_chart
  version      = var.chart_version
  include_crds = true
  # clusterName must be set or the chart's deployment.yaml template fails
  # template rendering entirely .
  values = [yamlencode(local.controller_values)]
}

locals {
  karpenter_crd_documents = [
    for index, doc in try(tolist(data.helm_template.karpenter_crds.crds), values(data.helm_template.karpenter_crds.crds), []) : {
      key   = "karpenter#${index}"
      value = trimspace(doc)
    }
    if trimspace(doc) != ""
  ]

  karpenter_crd_manifests = {
    for item in local.karpenter_crd_documents : item.key => yamldecode(item.value)
  }
}

resource "kubernetes_manifest" "karpenter_crds" {
  for_each = local.karpenter_crd_manifests

  manifest = each.value

  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
    "metadata.creationTimestamp",
    "spec.preserveUnknownFields",
    "spec.names.listKind",
    "spec.names.categories",
  ]

  # No prevent_destroy (removed 2026-08-02, explicit user decision): matches modules/crds -- this
  # repo intentionally supports `terragrunt run --all destroy` as a single-command full teardown.
  # See modules/crds/main.tf's chart_crds resource for the full rationale and residual tradeoff.
}

data "talos_machine_configuration" "worker" {
  talos_version      = var.talos_version
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  kubernetes_version = var.kubernetes_version
  machine_type       = "worker"
  machine_secrets    = var.talos_machine_secrets
  docs               = false
  examples           = false

  # Match the cloud-network bootstrap used by the upstream cluster module.
  # The machine configuration is kept in the Kubernetes Secret below and is
  # never written to a tracked file.
  config_patches = [
    # Match the upstream hcloud-k8s worker baseline. In particular, the
    # external cloud-provider kubelet setting allows hcloud CCM to initialize
    # the node, assign providerID, and publish cloud labels.
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            "cloud-provider"             = "external"
            "rotate-server-certificates" = true
          }
          nodeIP = {
            validSubnets = ["10.0.0.0/16"]
          }
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "LinkConfig"
      name       = "eth0"
      up         = true
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "DHCPv4Config"
      name       = "eth0"
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "LinkConfig"
      name       = "eth1"
      up         = true
      mtu        = 1450
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "DHCPv4Config"
      name       = "eth1"
    }),
  ]
}

resource "kubernetes_secret_v1" "worker_machineconfig" {
  metadata {
    name      = local.worker_machineconfig_secret_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "karpenter.hetzner.cloud/type" = "talos-worker-machineconfig"
    }
  }

  type = "Opaque"

  data = {
    "worker.yaml" = data.talos_machine_configuration.worker.machine_configuration
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "helm_release" "karpenter" {
  name             = var.release_name
  namespace        = var.namespace
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.chart_version
  create_namespace = var.create_namespace
  skip_crds        = true
  values           = [yamlencode(local.controller_values)]

  postrender = {
    binary_path = "/usr/bin/python3"
    args        = ["${path.module}/postrender.py"]
  }

  depends_on = [
    kubernetes_namespace_v1.this,
    kubernetes_secret_v1.hcloud_token,
    kubernetes_secret_v1.worker_machineconfig,
    kubernetes_manifest.karpenter_crds,
  ]
}

resource "kubernetes_manifest" "nodeclass" {
  manifest = {
    apiVersion = "karpenter.hetzner.cloud/v1"
    kind       = "HCloudNodeClass"
    metadata = {
      name = var.nodeclass_name
    }
    spec = merge(
      {
        locations = var.locations
        networkID = data.hcloud_network.cluster.id
        imageSelector = {
          family   = "talos"
          selector = local.image_selector
        }
        placementGroupStrategy = "spread"
        enablePublicIPv4       = var.public_ipv4_enabled
        enablePublicIPv6       = var.public_ipv6_enabled
        userDataSecretRef = {
          namespace = kubernetes_secret_v1.worker_machineconfig.metadata[0].namespace
          name      = kubernetes_secret_v1.worker_machineconfig.metadata[0].name
          key       = "worker.yaml"
        }
        labels = merge(
          {
            cluster     = var.cluster_name
            managed-by  = "karpenter"
            environment = var.environment
          },
          var.nodeclass_labels,
        )
      },
      var.nodeclass_spec_overrides,
    )
  }

  depends_on = [kubernetes_manifest.karpenter_crds]
}

resource "kubernetes_manifest" "nodepool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = var.nodepool_name
    }
    spec = merge(
      {
        template = {
          metadata = {
            labels = merge(
              {
                "workload-class" = "worker"
              },
              var.nodepool_template_labels,
            )
          }
          spec = {
            nodeClassRef = {
              group = "karpenter.hetzner.cloud"
              kind  = "HCloudNodeClass"
              name  = var.nodeclass_name
            }
            requirements = [
              {
                key      = "kubernetes.io/arch"
                operator = "In"
                values   = var.architectures
              },
              {
                key      = "node.kubernetes.io/instance-type"
                operator = "In"
                values   = var.server_types
              },
              {
                key      = "topology.kubernetes.io/zone"
                operator = "In"
                values   = var.locations
              },
            ]
          }
        }
        limits = {
          cpu = var.worker_cpu_limit
        }
        disruption = {
          consolidationPolicy = "WhenEmptyOrUnderutilized"
          consolidateAfter    = "30s"
        }
      },
      var.nodepool_spec_overrides,
    )
  }

  depends_on = [kubernetes_manifest.nodeclass]
}
