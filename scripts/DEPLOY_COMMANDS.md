# Deploy commands (build + push + run migrations + rollout)

Prerequisite: pick a tag (example `v1.0.0`) and run from repo root.

1) Build backend binary
```bash
cd backend
go mod tidy
CGO_ENABLED=0 GOOS=linux go build -o server .
cd ..
```

2) Build and push image
```bash
TAG="v1.0.0"
IMAGE="ricardohdc/shisha-tracker-nextgen-backend:${TAG}"
docker build -t "${IMAGE}" ./backend
docker push "${IMAGE}"
```
If you cannot push to a remote registry, save and import into your cluster runtime:
```bash
docker save -o /tmp/backend-${TAG}.tar ${IMAGE}
# import into containerd: (adjust to your cluster runtime)
ctr images import /tmp/backend-${TAG}.tar
rm /tmp/backend-${TAG}.tar
```

3) Ensure database is applied (only if not already)
```bash
kubectl apply -f k8s/cockroachdb.yaml
kubectl wait --for=condition=ready pod -l app=shisha-cockroachdb --timeout=180s || true
```

4) Apply RBAC required for leader election
```bash
kubectl apply -f k8s/backend-rbac.yaml
```

5) Apply backend manifests (ConfigMap, Deployment with initContainer)
Keep the Deployment scaled to 0 or with command override until migrations done:
```bash
kubectl apply -f k8s/backend.yaml
kubectl scale deploy shisha-backend-mock --replicas=0
```

6) Update and run migration Job (one-shot)
- Edit [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1) and set the `image:` to the same `${IMAGE}` you pushed (or use your cluster import).
- Then:
```bash
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s
kubectl logs -f job/shisha-migrate
```
Alternatively, you can enable in-pod leader-election migrations by setting `MIGRATE_ON_START=true` on the Deployment (requires serviceAccountName `shisha-backend-sa` and RBAC applied). If using that, skip the Job.

7) Rollout backend
- Remove any temporary command override (script tries this):
```bash
kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
kubectl set image deploy/shisha-backend-mock backend-mock="${IMAGE}"
kubectl patch deployment shisha-backend-mock -p '{"spec":{"template":{"spec":{"serviceAccountName":"shisha-backend-sa"}}}}' || true
kubectl set env deploy/shisha-backend-mock MIGRATE_ON_START=true
kubectl scale deploy shisha-backend-mock --replicas=2
kubectl rollout status deploy/shisha-backend-mock
```

8) Verify logs and readiness
```bash
kubectl get pods -l app=shisha-backend-mock -o wide
kubectl logs <pod-name> -c run-migrations --tail=200
kubectl logs <pod-name> -c backend-mock --tail=200
kubectl get svc
curl -sS http://<service-ip-or-dns>:8080/api/healthz
```

Files referenced
- [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1)
- [`k8s/backend-rbac.yaml`](k8s/backend-rbac.yaml:1)
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
- [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
- [`k8s/cockroachdb.yaml`](k8s/cockroachdb.yaml:1)

Use these commands to complete the rebuild/push/migrate/rollout sequence. Adjust `TAG`/`IMAGE` as needed for your registry.