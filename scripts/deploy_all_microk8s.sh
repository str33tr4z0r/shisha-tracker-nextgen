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

# PreStage
run microk8s.kubectl apply -f k8s/PreStage/namespace.yaml
run microk8s.kubectl create secret generic shisha-couchdb-admin -n "$NAMESPACE" \
  --from-literal=username=shisha_admin \
  --from-literal=password=ichbin1AdminPasswort! \
  --from-literal=ERLANG_COOKIE="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | cut -c1-64)" \
  --from-literal=COUCHDB_USER=shisha_admin \
  --from-literal=COUCHDB_PASSWORD=ichbin1AdminPasswort!

run microk8s.kubectl apply -f k8s/PreStage/couchdb-storageclass.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/couchdb-pv.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/couchdb.yaml -n "$NAMESPACE"
#run microk8s.kubectl rollout status deployment/shisha-couchdb -n "$NAMESPACE" --timeout=120s

#Couchdb
run microk8s.kubectl apply -f k8s/database/couchdb-rbac.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/database/couchdb-config.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/database/couchdb-scripts-configmap.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/database/couchdb-headless.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/database/couchdb-service.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/database/couchdb-statefulset.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/database/couchdb-networkpolicy.yaml -n "$NAMESPACE"
run microk8s.kubectl rollout status statefulset/couchdb -n "$NAMESPACE" --timeout=240s

#Backend
run microk8s.kubectl apply -f k8s/backend/backend.yaml -n "$NAMESPACE"
run microk8s.kubectl rollout status deployment/shisha-backend-mock -n "$NAMESPACE" --timeout=120s

#Frontend
run microk8s.kubectl apply -f k8s/frontend/shisha-frontend-nginx-configmap.yaml -n "$NAMESPACE"
run microk8s.kubectl apply -f k8s/frontend/frontend.yaml -n "$NAMESPACE"
run microk8s.kubectl rollout status deployment shisha-frontend -n "$NAMESPACE" --timeout=120s
run microk8s.kubectl apply -f k8s/frontend/ingress.yaml -n "$NAMESPACE"
#run microk8s.kubectl patch svc shisha-frontend -n "$NAMESPACE" --type='merge' -p '{"spec":{"externalIPs":["10.11.12.13"]}}'

#HPA / PDBs / Optionales Monitoring
#run microk8s.kubectl apply -f k8s/hpa/hpa-backend.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/hpa/hpa-frontend.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/pdb/pdb-backend.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/pdb/pdb-frontend.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/hpa/couchdb-hpa.yaml -n "$NAMESPACE"
#run microk8s.kubectl apply -f k8s/pdb/couchdb-pdb.yaml -n "$NAMESPACE"

#scale couchdb
run microk8s.kubectl scale statefulset couchdb --replicas=3 -n "$NAMESPACE"

#PostStage (optional)
#run microk8s.kubectl apply -f k8s/PostStage/shisha-sample-data.yaml -n "$NAMESPACE"
#srun microk8s.kubectl logs -l job-name=shisha-sample-data -n "$NAMESPACE" --tail=200


# 9) Final checks
echo 'Final resource check (filtered by name '"$NAMESPACE"')'
run microk8s.kubectl get all -A | grep "$NAMESPACE" || true
run microk8s.kubectl get pvc -A | grep "$NAMESPACE" || true
run microk8s.kubectl get pv | grep "$NAMESPACE" || true

echo "deploy script finished."