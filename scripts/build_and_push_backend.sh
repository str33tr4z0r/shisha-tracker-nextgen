#!/bin/bash
set -euo pipefail
IMAGE="ricardohdc/shisha-tracker-nextgen-backend:latest"
BUILD_CONTEXT="./backend"
DOCKERFILE="${BUILD_CONTEXT}/Dockerfile"

if [ ! -f "$DOCKERFILE" ]; then
  echo "Dockerfile not found at $DOCKERFILE" >&2
  exit 1
fi

echo "Building $IMAGE from $BUILD_CONTEXT using host network..."
#sudo docker build -f "$DOCKERFILE" -t "$IMAGE" --network=host "$BUILD_CONTEXT"
sudo docker build --network=host -f backend/Dockerfile -t ricardohdc/shisha-tracker-nextgen-backend:latest .
#echo "Login to Docker Hub (you can use username ricardohdc)"
#read -p "Docker Hub username: " USER
#read -s -p "Docker Hub password or token: " PASS
#echo

#echo "$PASS" | sudo docker login --username "$USER" --password-stdin

echo "Pushing $IMAGE..."
sudo docker push "$IMAGE"

echo "Done. Local image:"
sudo docker images --format "REPO:TAG={{.Repository}}:{{.Tag}} ID={{.ID}} SIZE={{.Size}}" "$IMAGE" || true