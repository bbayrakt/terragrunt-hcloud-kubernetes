---
title: Native Sidecar `dind` Container Misplaced Under `containers:` Instead of `initContainers:` Would Fail All ARC Runner Pod Validation
date: 2026-08-01
category: integration-issues
module: arc-runners
problem_type: integration_issue
component: tooling
symptoms:
  - "Kubernetes API rejects Pod creation whenever restartPolicy: Always is set on an entry under containers: (only initContainers[] permits it), so every ARC runner Pod based on this scale set spec would fail validation and never be created"
  - "ArgoCD's Application-level health check for the AutoscalingRunnerSet custom resource still reports Synced/Healthy, masking the failure since health evaluation happens at the CR level, not the eventual Pod"
  - "The dind sidecar container block was nested under containers: in platform/arc-runners/values.yaml immediately after the initContainers: entries, following the upstream gha-runner-scale-set chart's own commented-out reference blueprint but misplaced due to misread indentation"
  - "The failure would only surface when a real GitHub Actions workflow is dispatched and the ARC controller attempts to scale up an actual runner Pod, not during helm template/lint or ArgoCD sync"
  - "helm template/lint and terragrunt validate do not catch this bug because Pod admission-time restartPolicy validation is not enforced by chart templating or offline static validation tooling"
root_cause: wrong_api
resolution_type: code_fix
severity: critical
related_components: [arc-systems, gha-runner-scale-set, kubernetes-pod-spec]
tags: [kubernetes, helm, actions-runner-controller, sidecar-containers, restartpolicy, pod-validation, argocd-health-check, code-review]
---

# Native Sidecar `dind` Container Misplaced Under `containers:` Instead of `initContainers:` Would Fail All ARC Runner Pod Validation

## Problem

A hand-authored Docker-in-Docker (`dind`) sidecar container in `platform/arc-runners/values.yaml`
was placed under the pod spec's `containers:` list with `restartPolicy: Always` set — a
combination the Kubernetes API rejects outright, since `restartPolicy` is only a valid field on
`initContainers[]` entries. Had this shipped, every CI runner Pod for this ARC (`actions-runner-
controller`) scale set would have failed Pod creation and could never run a GitHub Actions job.

## Symptoms

Caught in code review before this ever ran against a live cluster; these are the symptoms that
would have surfaced if it had shipped, and what to watch for when reviewing a similar hand-authored
pod spec:

- Pod creation rejected by the Kubernetes API with an error resembling
  `spec.containers[1].restartPolicy: Forbidden: may not be set for non-init containers`, visible
  via `kubectl describe pod <runner-pod>` or `kubectl get events`.
- The affected Pods never reach `Running`; the `AutoscalingRunnerSet`'s controller-managed Pod
  objects show a persistent creation failure rather than terminating cleanly.
- ArgoCD's Application health check — evaluated against the `AutoscalingRunnerSet` CRD instance,
  not the runtime Pod — still reports **Synced/Healthy**, masking the failure at the platform
  layer entirely.
- The failure only becomes visible much later and indirectly: a real GitHub Actions workflow run
  dispatches a job that queues forever with no runner ever picking it up, and no explicit
  platform-level alert fires.
- `helm template`/`helm lint` show no error at all — neither performs full Kubernetes API
  schema/admission validation, so the invalid Pod spec renders and lints cleanly.

## What Didn't Work

The bug was introduced while hand-copying the upstream `actions/actions-runner-controller`
`gha-runner-scale-set` chart's own commented-out `containerMode.type=dind` reference blueprint
(obtainable via `helm show values oci://ghcr.io/actions/actions-runner-controller-charts/gha-
runner-scale-set --version 0.13.1`) into a hand-authored `template.spec` — necessary because that
chart's `containerMode.type: dind` convenience field is documented as mutually exclusive with
per-volume `emptyDir.sizeLimit` customization, which the enclosing change also needed.

The upstream blueprint nests **both** `init-dind-externals` and `dind` under a single
`initContainers:` list, with only `runner` under `containers:`. The mistake happened by misreading
the blueprint's indentation and visually splitting the list at the `dind` entry — treating it as
the start of a new top-level `containers:` block instead of a continuation of `initContainers:`.
Concretely, the blueprint is one flat list of two dash-prefixed items under `initContainers:`, and
the fault was inserting a `containers:` key between the first (`init-dind-externals`) and second
(`dind`) list items — effectively reconstructing the block from memory/visual scanning rather than
copying the exact key/indentation structure verbatim.

## Solution

Move `dind` back into `initContainers:` as the second entry (right after `init-dind-externals`),
keeping only `runner` under `containers:`.

Before (bug):

```yaml
      initContainers:
        - name: init-dind-externals
          image: ghcr.io/actions/actions-runner:latest
          command: ["cp", "-r", "/home/runner/externals/.", "/home/runner/tmpDir/"]
          volumeMounts:
            - name: dind-externals
              mountPath: /home/runner/tmpDir
      containers:
        - name: dind
          image: docker:dind
          securityContext:
            privileged: true
          restartPolicy: Always
          # ...args, env, startupProbe, resources, volumeMounts...
        - name: runner
          image: ghcr.io/actions/actions-runner:latest
          # ...
```

After (fixed):

```yaml
      initContainers:
        - name: init-dind-externals
          image: ghcr.io/actions/actions-runner:latest
          command: ["cp", "-r", "/home/runner/externals/.", "/home/runner/tmpDir/"]
          volumeMounts:
            - name: dind-externals
              mountPath: /home/runner/tmpDir
        - name: dind
          image: docker:dind
          securityContext:
            privileged: true
          restartPolicy: Always
          # ...args, env, startupProbe, resources, volumeMounts...
      containers:
        - name: runner
          image: ghcr.io/actions/actions-runner:latest
          # ...
```

The diff is purely structural: `dind` moves up to become the second list item under
`initContainers:`, and `containers:` moves down to appear only once, immediately before `runner`.

## Why This Works

Kubernetes' native sidecar container pattern (GA in Kubernetes 1.29+) only activates
`restartPolicy: Always` semantics for entries in `initContainers[]`. An init container marked
`restartPolicy: Always` starts before the pod's regular containers (in list order) but, unlike a
normal init container, does not run to completion — it keeps running for the entire lifetime of
the pod, exactly like a "real" sidecar. This is precisely the behavior needed for the `dind` Docker
daemon: it must be up and healthy before the `runner` container starts (hence its position after
`init-dind-externals` but before `containers:`), and it must keep running for as long as the
runner Pod exists to service Docker commands issued by the CI job.

Kubernetes' API validation enforces that `restartPolicy` is meaningful only to `initContainers[]`
— setting it on any entry in `containers:` is rejected outright, because ordinary containers
already run for the pod's lifetime by definition and don't need this field to express that.
Placing `dind` in `initContainers:` with `restartPolicy: Always`, alongside the genuinely run-once
`init-dind-externals` init container and the ordinary long-running `runner` container, correctly
expresses all three different container lifecycles in one pod using the mechanism Kubernetes
actually provides for it.

## Prevention

- Add a CI/pre-merge check (or at minimum a documented manual step) that runs `helm template
  <chart> -f values.yaml | kubectl apply --dry-run=server -f -` (or an equivalent — `kubeconform`
  against a real API server, or a local `kind` cluster) for any hand-authored Kubernetes pod spec.
  `helm template`/`helm lint` render and lint YAML/chart-logic only — neither invokes Kubernetes
  API admission/schema validation, and both pass cleanly on an invalid Pod spec like this one.
  This exact gap is why the bug reached code review instead of being caught by CI.
- When hand-copying any upstream chart's own reference blueprint (via `helm show values <chart>`
  or similar), preserve the exact list nesting and indentation as given rather than reconstructing
  the structure from memory or a quick visual read — treat it as a copy-paste operation, not a
  re-typing/re-formatting one, especially for YAML list blocks that span a key boundary (as here,
  where two entries under one `initContainers:` list can look, at a glance, like they belong to
  separate top-level keys).
- Anchor any hand-authored blueprint-derived block with a code comment citing the exact upstream
  chart name and pinned version it was copied from, so future chart version bumps can be re-diffed
  against the current upstream blueprint rather than trusted to have stayed correct by inspection
  alone.
- In review, treat any `restartPolicy` field appearing on a container as a specific trigger to
  verify which list (`containers:` vs `initContainers:`) it lives under — a narrow, mechanically
  checkable signal that caught this bug and generalizes well to future PRs touching native sidecar
  containers.

## Related Issues

- `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`
  — a separate, naming-convention gotcha (Gotcha 4) found in the same PR/review, affecting a
  different static manifest (a `VerticalPodAutoscaler` object) in the same `arc-systems`/
  `arc-runners` area — different mechanism (ArgoCD Helm release naming vs. Kubernetes Pod
  validation), same review pass.
- `docs/plans/2026-08-01-002-feat-helm-chart-resource-management-plan.md` — the implementation
  plan this fix landed under (Implementation Unit U3).
