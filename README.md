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

After the script finishes — manual verification steps
1) Verify image is present
```bash
docker images | grep ricardohdc/shisha-tracker-nextgen-backend
microk8s ctr images ls | grep ricardohdc/shisha-tracker-nextgen-backend || true
```

2) Check migrations executed (choose Job or initContainer)
```bash
microk8s kubectl logs -f job/shisha-migrate
microk8s kubectl logs <pod-name> -c run-migrations --tail=200
microk8s kubectl logs <pod-name> -c backend-mock --tail=200
```

3) Check rollout & pods
```bash
microk8s kubectl rollout status deploy/shisha-backend-mock
microk8s kubectl get pods -l app=shisha-backend-mock -o wide
```

4) Remove overrides and scale to desired replicas
```bash
microk8s kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
microk8s kubectl scale deploy/shisha-backend-mock --replicas=2
```

Notes & recommendations
- initContainer approach: keep MIGRATE_ON_START unset; the initContainer in [`k8s/backend.yaml`](k8s/backend.yaml:1) will apply SQL from the ConfigMap before the app starts.
- Leader-election approach: set MIGRATE_ON_START=true and ensure RBAC (`k8s/backend-rbac.yaml`) is applied so one pod runs AutoMigrate safely.
- Prefer fixed image tags (avoid :latest) and run migrations as a separate CI step or one-shot Job before rolling the Deployment.
- If you cannot push to a registry, use docker save + microk8s ctr image import as noted in the script.

Files to review
- [`backend/main.go`](backend/main.go:1)
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
- [`k8s/backend-rbac.yaml`](k8s/backend-rbac.yaml:1)
- [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
- [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1)
