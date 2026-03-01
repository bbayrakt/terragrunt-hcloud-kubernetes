data "helm_template" "charts" {
  for_each = {
    for name, chart in var.charts : name => chart
    if try(chart.manage_crds, true)
  }

  name             = each.key
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  include_crds     = true
  kube_version     = try(each.value.kube_version, "1.33.0")
}

locals {
  crd_documents = flatten([
    for chart_name, rendered in data.helm_template.charts : [
      for index, doc in try(tolist(rendered.crds), values(rendered.crds), []) : {
        key   = "${chart_name}#${index}"
        value = trimspace(doc)
      }
      if trimspace(doc) != ""
    ]
  ])

  crd_manifests = {
    for item in local.crd_documents : item.key => yamldecode(item.value)
  }
}

resource "kubernetes_manifest" "chart_crds" {
  for_each = local.crd_manifests

  manifest = each.value

  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
    "metadata.creationTimestamp",
    "spec.preserveUnknownFields",
    "spec.names.listKind",
    "spec.names.categories",
  ]

  lifecycle {
    prevent_destroy = true
  }
}