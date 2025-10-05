#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/build_and_deploy_backend.sh v1.0.0
sudo docker build --network=host -t ricardohdc/shisha-tracker-nextgen-backend:latest ./backend
sudo docker push ricardohdc/shisha-tracker-nextgen-backend:latest