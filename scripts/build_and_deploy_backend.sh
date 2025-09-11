#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/build_and_deploy_backend.sh v1.0.0
TAG="${1:-v1.0.0}"
IMAGE="ricardohdc/shisha-tracker-nextgen-backend:${TAG}"

echo "Building backend binary..."
cd backend
go mod tidy
CGO_ENABLED=0 GOOS=linux go build -o server .
cd ..

echo "Building docker image ${IMAGE}..."
docker build -t "${IMAGE}" ./backend

echo "Pushing image to registry..."
docker push "${IMAGE}"

echo "Update Deployment image..."
microk8s kubectl set image deploy/shisha-backend-mock backend-mock=\"${IMAGE}\"

echo "Remove temporary command override (if present)"
microk8s kubectl patch deploy shisha-backend-mock --type='json' -p='[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true

echo "Wait for rollout to complete..."
microk8s kubectl rollout status deploy/shisha-backend-mock

echo "Show pods and logs (example):"
microk8s kubectl get pods -l app=shisha-backend-mock -o wide
echo "  Logs from app container (backend-mock):"
microk8s kubectl logs -l app=shisha-backend-mock -c backend-mock --tail=200

echo "If you cannot push to a registry, import the image into microk8s instead:"
echo "  docker save -o /tmp/backend-${TAG}.tar ${IMAGE}"
echo "  microk8s ctr image import /tmp/backend-${TAG}.tar && rm /tmp/backend-${TAG}.tar"

echo "Done."