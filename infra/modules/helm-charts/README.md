# Helm Charts Module

Installs Helm charts declared in a shared `helm_charts` map using `helm_release`.

## Behavior

- Installs only charts where `install = true` (default: true)
- Uses `manage_crds` to control CRD strategy per chart:
  - `manage_crds = true` (default): Helm uses `skip_crds = true`, CRDs are expected to be applied by the `crds` stack
  - `manage_crds = false`: Helm uses `skip_crds = false`, so CRDs can be installed by the chart itself
- Creates target namespaces automatically

## Input

```hcl
charts = {
  chart_key = {
    repository  = "oci://example/charts"
    chart       = "my-chart"
    version     = "1.0.0"
    namespace   = "my-namespace"
    release_name = "my-release" # optional
    values       = {}             # optional
    manage_crds  = true           # optional, consumed by CRDs stack
    install      = true           # optional
  }
}
```
