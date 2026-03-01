locals {
  enabled_charts = {
    for name, chart in var.charts : name => chart
    if try(chart.install, true)
  }

  wave_1 = { for name, chart in local.enabled_charts : name => chart if try(chart.priority, 1) == 1 }
  wave_2 = { for name, chart in local.enabled_charts : name => chart if try(chart.priority, 1) == 2 }
  wave_3 = { for name, chart in local.enabled_charts : name => chart if try(chart.priority, 1) == 3 }

  # Collect namespaces that need pre-creation (skip existing ones)
  secret_namespaces = toset([
    for name, secret in var.secrets : secret.namespace
    if try(secret.create_namespace, true)
  ])
}

# Pre-create namespaces needed by secrets
resource "kubernetes_namespace_v1" "pre_created" {
  for_each = local.secret_namespaces

  metadata {
    name = each.value
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}

# Pre-chart secrets
resource "kubernetes_secret_v1" "pre_chart" {
  for_each = var.secrets

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  type = try(each.value.type, "Opaque")

  data = each.value.data

  depends_on = [kubernetes_namespace_v1.pre_created]
}

# Wave 1 (default)
resource "helm_release" "wave_1" {
  for_each = local.wave_1

  name             = coalesce(try(each.value.release_name, null), each.key)
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  namespace        = each.value.namespace
  create_namespace = true
  skip_crds        = true

  values = [
    yamlencode(try(each.value.values, {}))
  ]

  depends_on = [kubernetes_secret_v1.pre_chart]
}

# Wave 2 – waits for all wave-1 releases
resource "helm_release" "wave_2" {
  for_each = local.wave_2

  name             = coalesce(try(each.value.release_name, null), each.key)
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  namespace        = each.value.namespace
  create_namespace = true
  skip_crds        = true

  values = [
    yamlencode(try(each.value.values, {}))
  ]

  depends_on = [helm_release.wave_1]
}

# Wave 3 – waits for all wave-2 releases
resource "helm_release" "wave_3" {
  for_each = local.wave_3

  name             = coalesce(try(each.value.release_name, null), each.key)
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  namespace        = each.value.namespace
  create_namespace = true
  skip_crds        = true

  values = [
    yamlencode(try(each.value.values, {}))
  ]

  depends_on = [helm_release.wave_2]
}
