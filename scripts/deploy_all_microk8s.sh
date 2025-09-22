#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=shisha

usage() {
  cat <<EOF
Usage: $0 [--namespace NAME] [--dry-run] [--nuke-pv]
  --namespace NAME  Namespace to create resources from (default: shisha)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

run() {
    echo "[RUN] $*"
    eval "$@"
}

echo "Namespace: $NAMESPACE"

run microk8s.kubectl apply -f k8s/namespace.yaml
run microk8s.kubectl create secret generic shisha-couchdb-admin -n "$NAMESPACE" \
  --from-literal=username=ichbineinadmin \
  --from-literal=password=ichbin1AdminPasswort!
run microk8s.kubectl apply -f k8s/couchdb-storage-class.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/couchdb-pv.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/couchdb.yaml -n "$NAMESPACE"
run microk8s.kubectl rollout status statefulset/shisha-couchdb -n "$NAMESPACE" --timeout=120s
#run microk8s.kubectl apply -f k8s/couchdb-init-job.yaml -n "$NAMESPACE"
# Wait for init job to complete before deploying backend
run microk8s.kubectl wait --for=condition=complete job/shisha-couchdb-init -n "$NAMESPACE" --timeout=120s
run microk8s.kubectl logs -l job-name=shisha-couchdb-init -n "$NAMESPACE" --tail=200 || true
run microk8s.kubectl apply -f k8s/backend.yaml
run microk8s.kubectl rollout status deployment/shisha-backend-mock -n "$NAMESPACE" --timeout=120s
run microk8s.kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/frontend.yaml -n "$NAMESPACE"
run microk8s.kubectl rollout status deployment/shisha-frontend -n "$NAMESPACE" --timeout=120s
run microk8s.kubectl apply -f k8s/ingress.yaml -n "$NAMESPACE"
#run microk8s.kubectl patch svc shisha-frontend -n "$NAMESPACE" --type='merge' -p '{"spec":{"externalIPs":["10.11.12.13"]}}'

#Daten Bank Scalieren Optional
run microk8s.kubectl scale statefulset shisha-couchdb --replicas=3 -n "$NAMESPACE"
run microk8s.kubectl rollout status statefulset/shisha-couchdb -n "$NAMESPACE" --timeout=300s

#HPA / PDBs / Optionales Monitoring
run microk8s.kubectl apply -f k8s/hpa-backend.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/hpa-frontend.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/hpa-couchdb.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/pdb-backend.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/pdb-frontend.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/pdb-couchdb.yaml -n "$NAMESPACE"

#Sample Daten Optional 
run microk8s.kubectl apply -f k8s/shisha-sample-data.yaml -n "$NAMESPACE"
run microk8s.kubectl logs -l job-name=shisha-sample-data -n "$NAMESPACE" --tail=200



run microk8s.kubectl get statefulset,service,pods,pvc,hpa,pdb,jobs -n "$NAMESPACE" -o wide


# 9) Final checks
echo 'Final resource check (filtered by name '"$NAMESPACE"')'
run microk8s.kubectl get all -A | grep "$NAMESPACE" || true
run microk8s.kubectl get pvc -A | grep "$NAMESPACE" || true
run microk8s.kubectl get pv | grep "$NAMESPACE" || true

echo "deploy script finished."