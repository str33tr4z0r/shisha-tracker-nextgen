# Shisha Tracker — Deployment & Migration Notes

Summary of recent changes
- Removed leader-election migration logic (migrations are not needed with PocketBase).
- RBAC manifest for leader election (`k8s/backend-rbac.yaml`) removed.
- initContainer-based SQL migrations removed from `k8s/backend.yaml`.
- Migration Job (`k8s/migration-job.yaml`) updated to use PocketBase environment (if needed).
- Updated build/deploy helper script [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1).

Quick: run the build script
```bash
chmod +x scripts/build_and_deploy_backend.sh
./scripts/build_and_deploy_backend.sh v1.0.0
```

What the script does
- run go mod tidy and build a linux/static backend binary
- docker build and push image ricardohdc/shisha-tracker-nextgen-backend:vX
- update Deployment image and wait for rollout (no RBAC or leader-election required for PocketBase)
- remove temporary command overrides and print example logs

## Recommended k8s YAML apply order

Apply manifests in this order to avoid races and ensure the database and RBAC are available before the backend:

1. PocketBase (charts/pocketbase) — deploy PocketBase for local/dev storage (StatefulSet / Service / PVCs) or run PocketBase via docker/compose.
2. [`k8s/backend.yaml`](k8s/backend.yaml:1) — Backend Deployment (no DB initContainer). Apply this after you have built and pushed/imported the backend image.
3. (Optional) [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1) — usually not needed; updated to use PocketBase env if used.
4. [`k8s/frontend.yaml`](k8s/frontend.yaml:1) and any remaining frontend/service manifests.

Example sequence (generic kubectl + container runtime):
```bash
# Deploy PocketBase (local/dev)
# helm install shisha-pocketbase charts/pocketbase
kubectl apply -f k8s/backend.yaml

# after building/pushing/importing the backend image:
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s

# then remove any manual command override and scale the backend up
kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
kubectl scale deploy shisha-backend-mock --replicas=2

# finally apply frontend
kubectl apply -f k8s/frontend.yaml
```

Notes:
- For legacy SQL backends: run migrations as a CI step or one-shot Job before rolling the Deployment. For the default PocketBase setup, automatic in‑pod leader‑election migrations are not used.
After the script finishes — manual verification steps
1) Verify image is present
```bash
docker images | grep ricardohdc/shisha-tracker-nextgen-backend
# or, if using containerd directly:
ctr images ls | grep ricardohdc/shisha-tracker-nextgen-backend || true
```

2) Check logs and readiness
```bash
kubectl logs -f job/shisha-migrate
kubectl logs <pod-name> -c backend-mock --tail=200
```

3) Check rollout & pods
```bash
kubectl rollout status deploy/shisha-backend-mock
kubectl get pods -l app=shisha-backend-mock -o wide
```

4) Remove overrides and scale to desired replicas
```bash
kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
kubectl scale deploy shisha-backend-mock --replicas=2
```

Notes & recommendations
- initContainer approach: keep MIGRATE_ON_START unset; the initContainer in [`k8s/backend.yaml`](k8s/backend.yaml:1) will apply SQL from the ConfigMap before the app starts.
- Leader-election approach: set MIGRATE_ON_START=true and ensure RBAC (`k8s/backend-rbac.yaml`) is applied so one pod runs AutoMigrate safely.
- Prefer fixed image tags (avoid :latest) and run migrations as a separate CI step or one-shot Job before rolling the Deployment.
- If you cannot push to a registry, use docker save and import the image into your cluster's container runtime. Example:
  - docker save -o /tmp/backend-<tag>.tar ricardohdc/shisha-tracker-nextgen-backend:<tag>
  - ctr images import /tmp/backend-<tag>.tar   # for containerd users
  - OR load into a cluster-local registry if available

Files to review
- [`backend/main.go`](backend/main.go:1)
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
- [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
- [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1)
