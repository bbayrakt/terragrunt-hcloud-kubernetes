import sys
import yaml

# The upstream provider chart (2.0.0) does not expose pod scheduling values.
# Pin the controller deployment to the cluster's single static "system"
# worker node (nodepool=system, created by the kubernetes-cluster module)
# rather than letting it float onto any untainted node - including nodes
# Karpenter itself manages and may later consolidate away.
SYSTEM_NODE_SELECTOR = {"nodepool": "system"}

docs = list(yaml.safe_load_all(sys.stdin.read()))
for doc in docs:
    if not doc or doc.get("kind") != "Deployment":
        continue
    pod_spec = doc.setdefault("spec", {}).setdefault("template", {}).setdefault("spec", {})
    pod_spec["nodeSelector"] = dict(SYSTEM_NODE_SELECTOR)

yaml.safe_dump_all(docs, sys.stdout, explicit_start=True, sort_keys=False)
