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

Apply manifests in this order to avoid races and ensure the database is available before the backend:

1. PocketBase — deploy PocketBase for local/dev storage:
   - Either use the chart: `helm install shisha-pocketbase charts/pocketbase`
   - Or apply the manifest: `kubectl apply -f k8s/pocketbase.yaml`
2. [`k8s/backend.yaml`](k8s/backend.yaml:1) — Backend Deployment.
   - Keep the Deployment scaled to 0 or use a command override until the image has been pushed/imported.
3. (Optional) [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1) — run as a one-shot Job if you need to apply SQL migrations for a legacy SQL backend (set image to the pushed/imported backend image).
4. [`k8s/hpa-pocketbase.yaml`](k8s/hpa-pocketbase.yaml:1) — apply HPA (can be applied after the Deployment exists).
5. [`k8s/frontend.yaml`](k8s/frontend.yaml:1) and any remaining frontend/service manifests.

Example sequence (generic kubectl + container runtime):
```bash
# Deploy PocketBase (local/dev)
# helm install shisha-pocketbase charts/pocketbase
kubectl apply -f k8s/pocketbase.yaml

# apply backend manifests in "disabled" state (scale 0 or command override)
kubectl apply -f k8s/backend.yaml
kubectl scale deploy shisha-backend-mock --replicas=0

# after building/pushing/importing the backend image:
kubectl set image deploy/shisha-backend-mock backend-mock=ricardohdc/shisha-tracker-nextgen-backend:v1.0.0

# run migration job (if needed)
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s
kubectl logs -f job/shisha-migrate

# remove any manual command override and scale the backend up
kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
kubectl scale deploy shisha-backend-mock --replicas=2
kubectl rollout status deploy/shisha-backend-mock

# apply HPA (if needed) and then frontend
kubectl apply -f k8s/hpa-pocketbase.yaml
kubectl apply -f k8s/frontend.yaml
```

Notes:
- For the default PocketBase setup: automatic in‑pod leader‑election migrations are not used. Use the migration Job or run migrations as a CI step for legacy SQL storage.
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
