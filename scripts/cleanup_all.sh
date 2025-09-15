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

# 1) Delete seed job/configmap
run kubectl delete -f k8s/couchdb-seed-job-from-configmap.yaml -n "$NAMESPACE" --ignore-not-found
run kubectl delete configmap shisha-couchdb-seed-config -n "$NAMESPACE" --ignore-not-found
run kubectl delete job shisha-couchdb-seed -n "$NAMESPACE" --ignore-not-found

# 2) Delete frontend and backend
run kubectl delete -f k8s/frontend.yaml -n "$NAMESPACE" --ignore-not-found
run kubectl delete -f k8s/backend.yaml -n "$NAMESPACE" --ignore-not-found

# 3) Delete CouchDB deployment & service
run kubectl delete -f k8s/couchdb.yaml -n "$NAMESPACE" --ignore-not-found

# 4) Delete secrets and configmaps
run kubectl delete secret shisha-couchdb-admin -n "$NAMESPACE" --ignore-not-found
run kubectl delete configmap shisha-frontend-nginx -n "$NAMESPACE" --ignore-not-found

# 5) Delete PVC
run kubectl delete pvc shisha-couchdb-pvc -n "$NAMESPACE" --ignore-not-found

# 6) Optionally delete PV
if [ "$NUKE_PV" = true ]; then
  echo "Deleting PV 'shisha-couchdb-pv' (if exists)"
  run kubectl delete pv shisha-couchdb-pv --ignore-not-found
  echo "If the PV used a hostPath, you must remove data manually on the node."
  echo "Default hostPath from k8s/couchdb-pv.yaml: /var/lib/shisha/couchdb"
  echo "To remove on the node (run on the node or via SSH):"
  echo "  sudo rm -rf /var/lib/shisha/couchdb"
fi

# 7) Optional: delete namespace
echo "Deleting namespace '$NAMESPACE' (this removes any remaining resources)"
run kubectl delete namespace "$NAMESPACE" --ignore-not-found

# 8) Final checks
echo "Final resource check (filtered by name 'shisha')"
run kubectl get all -A | grep shisha || true
run kubectl get pvc -A | grep shisha || true
run kubectl get pv | grep shisha || true

echo "Cleanup script finished."