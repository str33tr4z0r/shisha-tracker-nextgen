#!/usr/bin/env bash
set -euo pipefail

# Build both frontend and backend Docker images and push to registry
# Usage: ./scripts/build_and_push_images.sh <tag> [registry_prefix]
# Example: ./scripts/build_and_push_images.sh v1.0.0 ricardohdc
# You can override docker command with DOCKER_CMD, e.g. DOCKER_CMD="sudo docker" ./scripts/...
TAG="${1:-v1.1.0}"
REGISTRY_PREFIX="${2:-ricardohdc}"
DOCKER_CMD="${DOCKER_CMD:-docker}"

BACKEND_IMAGE="${REGISTRY_PREFIX}/shisha-tracker-nextgen-backend:${TAG}"
FRONTEND_IMAGE="${REGISTRY_PREFIX}/shisha-tracker-nextgen-frontend:${TAG}"

echo "Using docker command: ${DOCKER_CMD}"
echo "Tag: ${TAG}"
echo "Backend image: ${BACKEND_IMAGE}"
echo "Frontend image: ${FRONTEND_IMAGE}"

echo "Building backend binary..."
pushd backend > /dev/null
go mod tidy
CGO_ENABLED=0 GOOS=linux go build -o server .
popd > /dev/null

echo "Building backend image ${BACKEND_IMAGE}..."
# Use repo root as build context so Dockerfile's COPY backend/... paths resolve
${DOCKER_CMD} build --network=host -t "${BACKEND_IMAGE}" -f backend/Dockerfile .

echo "Pushing backend image ${BACKEND_IMAGE}..."
${DOCKER_CMD} push "${BACKEND_IMAGE}"

echo "Frontend build will run inside the frontend Dockerfile (no local npm required)."
# The frontend Dockerfile's builder stage runs npm ci and npm run build,
# so we don't require npm on the host. Proceed to docker build below.

echo "Building frontend image ${FRONTEND_IMAGE}..."
${DOCKER_CMD} build --network=host -t "${FRONTEND_IMAGE}" ./frontend

echo "Pushing frontend image ${FRONTEND_IMAGE}..."
${DOCKER_CMD} push "${FRONTEND_IMAGE}"

echo "Done."