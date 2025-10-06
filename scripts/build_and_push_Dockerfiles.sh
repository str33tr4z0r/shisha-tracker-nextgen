#!/bin/bash
set -euo pipefail

#backend

sudo docker build --network=host --pull --no-cache -t ricardohdc/shisha-tracker-nextgen-backend:latest ./backend 
sudo docker push ricardohdc/shisha-tracker-nextgen-backend:latest

#frontend
sudo docker build --network=host --pull --no-cache -t ricardohdc/shisha-tracker-nextgen-frontend:latest ./frontend 
sudo docker push ricardohdc/shisha-tracker-nextgen-frontend:latest 
