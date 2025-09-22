#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-shisha}
ADMIN_USER=${ADMIN_USER:-shisha_admin}
ADMIN_PASS=${ADMIN_PASS:-shisha_password}
BACKEND_SVC=${BACKEND_SVC:-shisha-backend-mock:8080}

echo "Ensure namespace ${NAMESPACE}"
kubectl apply -f k8s/namespace.yaml

echo "Create admin secret (idempotent)"
kubectl -n "${NAMESPACE}" delete secret shisha-couchdb-admin >/dev/null 2>&1 || true
kubectl create secret generic shisha-couchdb-admin -n "${NAMESPACE}" --from-literal=username="${ADMIN_USER}" --from-literal=password="${ADMIN_PASS}"

echo "Apply PV"
kubectl apply -f k8s/couchdb-pv.yaml

echo "Deploy CouchDB (StatefulSet + Services)"
kubectl apply -f k8s/couchdb.yaml -n "${NAMESPACE}"
kubectl rollout status statefulset/shisha-couchdb -n "${NAMESPACE}" --timeout=180s

echo "Run init job (creates DB/index)"
kubectl apply -f k8s/migration-job.yaml -n "${NAMESPACE}"
kubectl wait --for=condition=complete job/shisha-couchdb-init -n "${NAMESPACE}" --timeout=120s || true

echo "Smoke test: verify CouchDB is reachable from a pod"
kubectl run --rm -n "${NAMESPACE}" smoke-curl --image=curlimages/curl --restart=Never --command -- sh -c \
  "until curl -sSf http://shisha-couchdb:5984/ >/dev/null 2>&1; do sleep 2; done; echo 'CouchDB reachable'; curl -sS -u \"${ADMIN_USER}:${ADMIN_PASS}\" http://shisha-couchdb:5984/shisha || true"

echo "Smoke test: verify backend health (if deployed)"
kubectl run --rm -n "${NAMESPACE}" smoke-curl-backend --image=curlimages/curl --restart=Never --command -- sh -c \
  "if curl -sSf http://${BACKEND_SVC}/api/healthz >/dev/null 2>&1; then echo 'Backend reachable'; else echo 'Backend not reachable'; fi"

echo "Cluster resources (summary):"
kubectl get statefulset,service,pods,pvc,hpa,pdb,jobs -n "${NAMESPACE}" -o wide

echo "Smoke tests completed."