# Container IDs (mit klarer Kennzeichnung) — Docker und Kubernetes

Verwendet die Service-Namen aus [`docker-compose.yml`](docker-compose.yml:1) und die Labels aus [`k8s/backend.yaml`](k8s/backend.yaml:1) sowie [`k8s/frontend.yaml`](k8s/frontend.yaml:1).

Docker Compose — Bash (zeigt Backend-Container-ID und darunter die Frontend-Container-ID)
[`bash()`](docker-compose.yml:1)
```bash
echo "BACKEND_CONTAINER_ID (backend container): $(docker-compose ps -q backend-mock)"
echo "FRONTEND_CONTAINER_ID (frontend container): $(docker-compose ps -q frontend)"
```

Docker Compose — PowerShell (zeigt Backend- und Frontend-Container-IDs)
[`powershell()`](docker-compose.yml:1)
```powershell
Write-Output "BACKEND_CONTAINER_ID (backend container): $(docker-compose ps -q backend-mock)"
Write-Output "FRONTEND_CONTAINER_ID (frontend container): $(docker-compose ps -q frontend)"
```

Docker (Fallback über docker ps) — Bash
[`bash()`](docker-compose.yml:1)
```bash
# Fallback: suche Container nach Namen, gebe Backend- und Frontend-ID getrennt aus
BACKEND=$(docker ps -q --filter "name=backend-mock" | head -n1)
FRONTEND=$(docker ps -q --filter "name=frontend" | head -n1)
echo "BACKEND_CONTAINER_ID (backend container): $BACKEND"
echo "FRONTEND_CONTAINER_ID (frontend container): $FRONTEND"
```

Kubernetes — erster Pod pro Label (gibt runtime-Präfix mit, z.B. docker:// oder containerd://)
[`bash()`](k8s/backend.yaml:1)
```bash
echo "BACKEND_CONTAINER_ID (backend container): $(kubectl get pods -l app=shisha-backend-mock -o jsonpath='{.items[0].status.containerStatuses[0].containerID}')"
echo "FRONTEND_CONTAINER_ID (frontend container): $(kubectl get pods -l app=shisha-frontend -o jsonpath='{.items[0].status.containerStatuses[0].containerID}')"
```

Kubernetes — alle Pods mit Container-IDs (nützlich bei mehreren Replicas)
[`bash()`](k8s/frontend.yaml:1)
```bash
kubectl get pods -l app=shisha-backend-mock -o jsonpath='{range .items[*]}BACKEND_POD: {.metadata.name} BACKEND_CONTAINER_ID: {.status.containerStatuses[0].containerID}{"\n"}{end}'
kubectl get pods -l app=shisha-frontend -o jsonpath='{range .items[*]}FRONTEND_POD: {.metadata.name} FRONTEND_CONTAINER_ID: {.status.containerStatuses[0].containerID}{"\n"}{end}'
```

Kubernetes — Container-ID ohne Runtime-Präfix (falls nur die rohe ID benötigt wird)
[`bash()`](k8s/backend.yaml:1)
```bash
# Beispiel: entferne docker:// oder containerd:// Präfix
kubectl get pods -l app=shisha-backend-mock -o jsonpath='{.items[0].status.containerStatuses[0].containerID}' \
  | sed -E 's|.*/||' \
  | xargs -I{} echo "BACKEND_CONTAINER_ID (backend container): {}"
kubectl get pods -l app=shisha-frontend -o jsonpath='{.items[0].status.containerStatuses[0].containerID}' \
  | sed -E 's|.*/||' \
  | xargs -I{} echo "FRONTEND_CONTAINER_ID (frontend container): {}"
```

Hinweise
- Die obenstehenden Zeilen geben explizit an, welche ID zur Backend- bzw. zur Frontend-Instanz gehört (wie gewünscht).
- Docker Compose verwendet die Service-Namen aus [`docker-compose.yml`](docker-compose.yml:1).
- Kubernetes-Selektoren verwenden das Label `app=shisha-backend-mock` bzw. `app=shisha-frontend` aus den Manifests.
- Kubernetes liefert IDs mit Runtime-Präfix (z.B. docker:// oder containerd://). Verwende die sed/xargs-Variante, wenn du nur die rohe ID ohne Präfix brauchst.
- Kopiere die Einzeiler in Skripte (sh / PowerShell) für wiederholte Nutzung.
---  
Hinweis: In den obigen Ausgaben bezieht sich "Container ID" standardmäßig auf den Backend-Container (Service: backend-mock).