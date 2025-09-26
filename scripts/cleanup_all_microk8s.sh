#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=shisha
DRY_RUN=false
NUKE_PV=false

usage() {
  cat <<EOF
Usage: $0 [--namespace NAME] [--dry-run] [--nuke-pv]
  --namespace NAME  Namespace to delete resources from (default: shisha)
  --dry-run         Show commands without executing
  --nuke-pv         Also delete PV and print hostPath removal instructions
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
#run kubectl delete -f k8s/couchdb-seed-job-from-configmap.yaml -n "$NAMESPACE" --ignore-not-found
#run kubectl delete configmap shisha-couchdb-seed-config -n "$NAMESPACE" --ignore-not-found
#run kubectl delete job shisha-couchdb-seed -n "$NAMESPACE" --ignore-not-found

# 2) Delete frontend and backend
run microk8s.kubectl delete -f k8s/frontend/frontend.yaml -n "$NAMESPACE" --ignore-not-found
run microk8s.kubectl delete -f k8s/backend/backend.yaml -n "$NAMESPACE" --ignore-not-found

# 3) Delete CouchDB deployment & service
run microk8s.kubectl delete -f k8s/basic-database/couchdb.yaml -n "$NAMESPACE" --ignore-not-found
#Delete Sample, if applied
run microk8s.kubectl delete -f k8s/PostStage/shisha-sample-data.yaml -n "$NAMESPACE" --ignore-not-found

# 4) Delete secrets and configmaps
run microk8s.kubectl delete secret shisha-couchdb-admin -n "$NAMESPACE" --ignore-not-found
run microk8s.kubectl delete configmap shisha-frontend-nginx -n "$NAMESPACE" --ignore-not-found

# 5) Delete PVC
run microk8s.kubectl delete pvc shisha-couchdb-pvc -n "$NAMESPACE" --ignore-not-found

# 6) Optionally delete PV
if [ "$NUKE_PV" = true ]; then
  echo "Deleting PV 'shisha-couchdb-pv' (if exists)"
  run microk8s.kubectl delete pv shisha-couchdb-pv --ignore-not-found
  echo "If the PV used a hostPath, you must remove data manually on the node."
  echo "Default hostPath from k8s/couchdb-pv.yaml: /var/lib/shisha/couchdb"
  echo "To remove on the node (run on the node or via SSH):"
  echo "  sudo rm -rf /var/lib/shisha/couchdb"
fi



# 7) Delte HPA and PDB
run microk8s.kubectl delete -f k8s/hpa/hpa-frontend.yaml -n "$NAMESPACE"  --ignore-not-found
run microk8s.kubectl delete -f k8s/hpa/hpa-backend.yaml -n "$NAMESPACE"  --ignore-not-found

run microk8s.kubectl delete -f k8s/pdb/pdb-backend.yaml -n "$NAMESPACE"  --ignore-not-found
run microk8s.kubectl delete -f k8s/pdb/pdb-backend.yaml -n "$NAMESPACE"  --ignore-not-found

# 8) Optional: delete namespace
run microk8s.kubectl delete -f k8s/frontend/ingress.yaml "$NAMESPACE" --ignore-not-found

# 9) Optional: delete namespace
echo "Deleting namespace '$NAMESPACE' (this removes any remaining resources)"
run microk8s.kubectl delete namespace "$NAMESPACE" --ignore-not-found

# 10) Final checks
echo "Final resource check (filtered by name 'shisha')"
run microk8s.kubectl get all -A | grep shisha || true
run microk8s.kubectl get pvc -A | grep shisha || true
run microk8s.kubectl get pv | grep shisha || true

echo "Cleanup script finished."