# Shisha Tracker — Deployment & Migration Notes

Summary of recent changes
- Implemented leader-election migration logic in [`backend/main.go`](backend/main.go:1).
- Added RBAC manifest for leader election at [`k8s/backend-rbac.yaml`](k8s/backend-rbac.yaml:1).
- Added initContainer-based SQL migration via [`k8s/backend.yaml`](k8s/backend.yaml:1).
- Added one-shot migration Job manifest [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1).
- Added build/deploy helper script [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1).

Quick: run the build script
```bash
chmod +x scripts/build_and_deploy_backend.sh
./scripts/build_and_deploy_backend.sh v1.0.0
```

What the script does
- run go mod tidy and build a linux/static backend binary
- docker build and push image ricardohdc/shisha-tracker-nextgen-backend:vX
- apply RBAC (`k8s/backend-rbac.yaml`) so leader-election can use Lease objects
- patch Deployment to use serviceAccountName=shisha-backend-sa
- set MIGRATE_ON_START=true and remove temporary command overrides
- wait for rollout and print example logs

## Recommended k8s YAML apply order

Apply manifests in this order to avoid races and ensure the database and RBAC are available before the backend:

1. [`k8s/cockroachdb.yaml`](k8s/cockroachdb.yaml:1) — provision the database (StatefulSet / Service / PVCs).
2. [`k8s/backend-rbac.yaml`](k8s/backend-rbac.yaml:1) — ServiceAccount + Role + RoleBinding needed for leader-election leases.
3. [`k8s/backend.yaml`](k8s/backend.yaml:1) — ConfigMap + initContainer + Deployment. You can keep the Deployment scaled to 0 or with a command override until the image and migrations are ready.
4. (Optional) [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1) — one-shot Job that runs the backend with --migrate-only. Apply this after you have built and pushed/imported the backend image.
5. [`k8s/frontend.yaml`](k8s/frontend.yaml:1) and any remaining frontend/service manifests.

Example sequence (generic kubectl + container runtime):
```bash
kubectl apply -f k8s/cockroachdb.yaml
kubectl apply -f k8s/backend-rbac.yaml
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
- If you prefer the initContainer approach, step 4 is optional — the initContainer will create the schema before the app starts.
- If you prefer leader-election AutoMigrate, ensure step 2 is applied before creating the Deployment and set MIGRATE_ON_START=true on the Deployment or run the one-shot Job.
After the script finishes — manual verification steps
1) Verify image is present
```bash
docker images | grep ricardohdc/shisha-tracker-nextgen-backend
# or, if using containerd directly:
ctr images ls | grep ricardohdc/shisha-tracker-nextgen-backend || true
```

2) Check migrations executed (choose Job or initContainer)
```bash
kubectl logs -f job/shisha-migrate
kubectl logs <pod-name> -c run-migrations --tail=200
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
- [`k8s/backend-rbac.yaml`](k8s/backend-rbac.yaml:1)
- [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
- [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1)
