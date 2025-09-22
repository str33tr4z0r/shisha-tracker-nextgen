#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${1:-shisha}
REPLICAS=${2:-5}
echo "Namespace: $NAMESPACE ; desired replicas: $REPLICAS"

ADMIN_SECRET=shisha-couchdb-admin
ADMIN_USER=$(kubectl get secret $ADMIN_SECRET -n $NAMESPACE -o jsonpath='{.data.username}' | base64 --decode)
ADMIN_PASSWORD=$(kubectl get secret $ADMIN_SECRET -n $NAMESPACE -o jsonpath='{.data.password}' | base64 --decode)

echo "Scaling StatefulSet to $REPLICAS..."
kubectl scale statefulset shisha-couchdb --replicas=$REPLICAS -n $NAMESPACE
kubectl rollout status statefulset/shisha-couchdb -n $NAMESPACE --timeout=300s

echo "Waiting for pods to be Ready..."
kubectl wait --for=condition=Ready pod -l app=shisha-couchdb -n $NAMESPACE --timeout=300s

echo "Pods:"
kubectl get pods -n $NAMESPACE -l app=shisha-couchdb -o wide

echo "Checking cluster membership via service endpoint..."
kubectl run --rm -n $NAMESPACE curl-membership --image=curlimages/curl --restart=Never --attach --command -- sh -c "curl -sS -u \"$ADMIN_USER:$ADMIN_PASSWORD\" http://shisha-couchdb:5984/_membership || true"

echo "Checking membership per pod (local API)..."
for i in $(seq 0 $((REPLICAS-1))); do
  POD=shisha-couchdb-$i
  echo "=== $POD ==="
  kubectl -n $NAMESPACE exec $POD -c couchdb -- curl -sS -u "$ADMIN_USER:$ADMIN_PASSWORD" http://localhost:5984/_membership || true
done

echo "Verifying shisha DB existence on pod0..."
kubectl -n $NAMESPACE exec shisha-couchdb-0 -c couchdb -- curl -sS -u "$ADMIN_USER:$ADMIN_PASSWORD" http://localhost:5984/shisha || true

echo "Done."