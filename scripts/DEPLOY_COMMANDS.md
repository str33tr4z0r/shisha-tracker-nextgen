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

3) Ensure storage is available (PocketBase)
```bash
# For local/dev use the provided PocketBase chart or run PocketBase as a container
# Example (Helm chart):
# helm install shisha-pocketbase charts/pocketbase
# or run PocketBase via docker-compose / your preferred method
```

4) Apply backend manifests (disabled until image is available)
```bash
# Apply Deployment but keep it scaled down so pods don't start before the image is available
kubectl apply -f k8s/backend.yaml
kubectl scale deploy shisha-backend-mock --replicas=0
```

5) Update and run migration Job (one-shot)
- Edit [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1) and set the `image:` to the same `${IMAGE}` you pushed (or use your cluster import).
- Then:
```bash
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s
kubectl logs -f job/shisha-migrate
```
Note: automatic in‑pod leader‑election migrations are not used for the default PocketBase setup. If you need SQL migrations for a legacy SQL backend, run the dedicated migration Job or perform migrations as a CI step before rollout.

6) Rollout backend
- Set the backend image, remove any temporary command override, then scale up and verify the rollout:
```bash
kubectl set image deploy/shisha-backend-mock backend-mock="${IMAGE}"
kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
kubectl scale deploy shisha-backend-mock --replicas=2
kubectl rollout status deploy/shisha-backend-mock
```

7) Apply HPA and frontend
```bash
# Apply HPA for PocketBase (if needed) after Deployment exists
kubectl apply -f k8s/hpa-pocketbase.yaml

# Then apply frontend manifests
kubectl apply -f k8s/frontend.yaml
```

8) Verify logs and readiness
```bash
kubectl get pods -l app=shisha-backend-mock -o wide
kubectl logs <pod-name> -c backend-mock --tail=200
kubectl get svc
curl -sS http://<service-ip-or-dns>:8080/api/healthz
```

Files referenced
- [`scripts/build_and_deploy_backend.sh`](scripts/build_and_deploy_backend.sh:1)
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
- [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
- [`charts/pocketbase/Chart.yaml`](charts/pocketbase/Chart.yaml:1)

Use these commands to complete the rebuild/push/migrate/rollout sequence. Adjust `TAG`/`IMAGE` as needed for your registry.