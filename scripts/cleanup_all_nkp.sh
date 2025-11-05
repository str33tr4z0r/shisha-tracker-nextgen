#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=shisha
DRY_RUN=false
# Default to nuking PVs in dev to ensure a full clean state. Use --no-nuke-pv (not implemented) to skip.
NUKE_PV=true

usage() {
  cat <<EOF
Usage: $0 [--namespace NAME] [--dry-run] [--nuke-pv]
  --namespace NAME  Namespace to delete resources from (default: shisha)
  --dry-run         Show commands without executing
  --nuke-pv         Also delete PVs (default: true)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    --nuke-pv) NUKE_PV=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] $*"
  else
    echo "[RUN] $*"
    eval "$@"
  fi
}

echo "Namespace: $NAMESPACE"
echo "Dry run: $DRY_RUN"
echo "Nuke PV: $NUKE_PV"

# 1) Delete seed job/configmap - DEPRECATED
#run kubectl delete -f k8s/NKP/couchdb-seed-job-from-configmap.yaml -n "$NAMESPACE" --ignore-not-found
#run kubectl delete configmap shisha-couchdb-seed-config -n "$NAMESPACE" --ignore-not-found
#run kubectl delete job shisha-couchdb-seed -n "$NAMESPACE" --ignore-not-found

# 2) Delete frontend and backend
run kubectl delete -f k8s/NKP/frontend/frontend.yaml -n "$NAMESPACE" --ignore-not-found
run kubectl delete -f k8s/NKP/backend/backend.yaml -n "$NAMESPACE" --ignore-not-found

# 3) Delete CouchDB StatefulSet, Deployments & Services (by manifest and by label)
# Delete manifest-driven resources (if present)
run kubectl delete -f k8s/NKP/database/couchdb-statefulset.yaml -n "$NAMESPACE" --ignore-not-found
#run kubectl delete -f k8s/NKP/database/couchdb-service.yaml -n "$NAMESPACE" --ignore-not-found
#run kubectl delete -f k8s/NKP/database/couchdb-headless.yaml -n "$NAMESPACE" --ignore-not-found
run kubectl delete -f k8s/NKP/basic-database/couchdb.yaml -n "$NAMESPACE" --ignore-not-found || true

# Delete any resources selected by label to catch manual creations
run kubectl -n "$NAMESPACE" delete statefulset -l app=couchdb --ignore-not-found
run kubectl -n "$NAMESPACE" delete svc -l app=couchdb --ignore-not-found
run kubectl -n "$NAMESPACE" delete deployment -l app=couchdb --ignore-not-found

# Delete Sample, if applied
run kubectl delete -f k8s/NKP/PostStage/shisha-sample-data.yaml -n "$NAMESPACE" --ignore-not-found

# 4) Delete secrets and configmaps
run kubectl delete secret shisha-couchdb-admin -n "$NAMESPACE" --ignore-not-found
run kubectl delete configmap shisha-frontend-nginx -n "$NAMESPACE" --ignore-not-found

# 5) Delete PVCs for CouchDB and related resources (by label/namespace)
run kubectl -n "$NAMESPACE" delete pvc -l app=couchdb --ignore-not-found || true
run kubectl -n "$NAMESPACE" delete pvc --all --ignore-not-found || true

# 6) Optionally delete PVs bound to this namespace or labelled for this app
if [ "$NUKE_PV" = true ]; then
  echo "Deleting PV 'shisha-couchdb-pv' (if exists)"
  run kubectl delete pv shisha-couchdb-pv --ignore-not-found
  echo "If the PV used a hostPath, you must remove data manually on the node."
  echo "Default hostPath from k8s/NKP/couchdb-pv.yaml: /var/lib/shisha/couchdb"
  echo "To remove on the node (run on the node or via SSH):"
  echo "  sudo rm -rf /var/lib/shisha/couchdb"
  sudo rm -rf /var/lib/shisha/couchdb
fi



# 7) Delete HPA and PDBs (if present)
run kubectl delete -f k8s/NKP/hpa/hpa-frontend.yaml -n "$NAMESPACE"  --ignore-not-found || true
run kubectl delete -f k8s/NKP/hpa/hpa-backend.yaml -n "$NAMESPACE"  --ignore-not-found || true
run kubectl -n "$NAMESPACE" delete hpa --all --ignore-not-found || true

run kubectl delete -f k8s/NKP/pdb/pdb-backend.yaml -n "$NAMESPACE"  --ignore-not-found || true
run kubectl delete -f k8s/NKP/pdb/pdb-frontend.yaml -n "$NAMESPACE"  --ignore-not-found || true
run kubectl -n "$NAMESPACE" delete pdb --all --ignore-not-found || true

# 8) Optional: delete ingress and related frontend objects
# delete by file and namespace and legacy location
run kubectl delete -f k8s/NKP/frontend/ingress.yaml -n "$NAMESPACE" --ignore-not-found || true
run kubectl delete -f k8s/NKP/PreStage/ingress-treafik.yaml --ignore-not-found || true

# 9) Optional: delete namespace
echo "Deleting namespace '$NAMESPACE' (this removes any remaining resources)"
run kubectl delete namespace "$NAMESPACE" --ignore-not-found

# 10) Final checks
echo "Final resource check (filtered by name/namespace '$NAMESPACE')"
run kubectl get all -A | grep "$NAMESPACE" || true
run kubectl get pvc -A | grep "$NAMESPACE" || true
run kubectl get pv | grep "$NAMESPACE" || true
#run kubectl get storageclass | grep couchdb || true

echo "Cleanup script finished."