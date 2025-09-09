# Shisha Tracker - Architektur & Deployment

Übersicht
Diese Repository enthält ein scaffold für eine Web-Applikation (Frontend: Vue 3 + Tailwind, Backend: Go + Gin + GORM) und Helm-Charts zur Bereitstellung in Kubernetes.

Projektstruktur
- [`frontend`](frontend:1): Vue 3 + Vite + Tailwind
- [`backend`](backend:1): Go (Gin + GORM)
- [`charts`](charts:1): Helm-Charts für frontend, backend und cockroachdb
- [`k8s`](k8s:1): zusätzliche Kubernetes-Infos

Voraussetzungen
- Kubernetes Cluster (multinode) mit StorageClass
- Helm 3
- kubectl konfiguriert für das Ziel-Cluster
- Eine Container-Registry (z. B. Docker Hub, GitHub Container Registry)

Vorbereitung: Images in Registry
1. Erstelle ein Registry-Secret:
   kubectl create secret docker-registry regcred --docker-server=<REGISTRY> --docker-username=<USER> --docker-password=<PASSWORD> --docker-email=<EMAIL> -n shisha
2. Setze in den jeweiligen `values.yaml` unter `image.repository` und `image.tag` deine Werte (siehe [`charts/backend/values.yaml`](charts/backend/values.yaml:1) und [`charts/frontend/values.yaml`](charts/frontend/values.yaml:1)).

Datenbank-Credentials / TLS
- CockroachDB benötigt initiale Secrets und gegebenenfalls TLS-Assets. Beispiel-Secret:
   kubectl create secret generic cockroachdb-root --from-literal=COCKROACH_PASSWORD='<STRONG_PASSWORD>' -n shisha
- Für produktive TLS-Setups generiere Zertifikate und lege sie als Secrets ab; Verweise befinden sich in [`charts/cockroachdb`](charts/cockroachdb:1).

Deployment-Schritte (Helm)
1. Namespace anlegen:
   kubectl create namespace shisha
2. Registry-Secret (siehe oben) in Namespace erstellen.
3. CockroachDB installieren (Beispiel mit lokalen Chart):
   helm upgrade --install cockroachdb charts/cockroachdb -n shisha -f charts/cockroachdb/values.yaml
   Hinweis: Setze `replicas: 3` und konfiguriere PVCs/storageClass in [`charts/cockroachdb/values.yaml`](charts/cockroachdb/values.yaml:1).
4. Backend installieren:
   helm upgrade --install shisha-backend charts/backend -n shisha -f charts/backend/values.yaml
   Achte auf `env.DB_DSN` bzw. `env.DATABASE_URL` in den Values für die Verbindung zur CockroachDB.
5. Frontend installieren:
   helm upgrade --install shisha-frontend charts/frontend -n shisha -f charts/frontend/values.yaml

Upgrade / Rollback
- Upgrade: helm upgrade --install <release> <chart> -f <values.yaml> -n shisha
- Rollback: helm rollback <release> <revision> -n shisha

HA & Best Practices
- Setze `replicaCount: >=3` für Backend/Frontend im `values.yaml`.
- PodAntiAffinity: in den Chart-Templates bereits vorbereitet, passe Labels anfallsweise an.
- Ressourcen: Requests/Limits in `values.yaml` definieren.
- Readiness/Liveness-Probes sind in den Chart-Templates enthalten und sollten an reale Endpunkte angepasst werden.

Storage & Backups
- PVCs werden per Chart angelegt; verwende eine StorageClass mit Replikation (z. B. provisioned by cloud provider).
- Für Backups nutze CockroachDB native Backups oder Velero; Backup-Anleitungen kommen später in [`k8s/backup`](k8s/backup:1).

Debugging / Lokale Entwicklung
- Für lokale Tests kann ein einfaches `docker-compose.yml` genutzt werden (nicht für Produktion). Dieser Inhalt wird später unter [`docker-compose.yml`](docker-compose.yml:1) ergänzt.

Hinweise zum Helm-Chart
- Charts enthalten Platzhalter für Secrets (siehe `values.yaml`), TLS-Keys und imagePullSecrets.
- Standard-Ports: Backend 8080, Frontend 80 (oder 3000 für dev).

Kontakt & Weiteres
- README: Weitere Details, Migrationsskripte und API-Dokumentation folgen in [`backend/README.md`](backend/README.md:1).# shisha-tracker-nextgen

## Manuelles Kubernetes‑Deployment (klassische YAML) — Reihenfolge und Befehle

Wenn du statt Helm die klassischen Kubernetes‑YAMLs verwenden möchtest, ist die empfohlene Reihenfolge und die minimalen Schritte wie folgt:

1) Namespace & Secrets
```bash
kubectl apply -f [`k8s/namespace.yaml`](k8s/namespace.yaml:1)
kubectl apply -f [`k8s/secrets.yaml`](k8s/secrets.yaml:1)
```

2) Datenbank (CockroachDB)
- Zuerst die StatefulSet/Service/YAMLs für CockroachDB anwenden und sicherstellen, dass PVCs gebunden sind und alle Pods READY melden:
```bash
kubectl apply -f [`k8s/cockroachdb-service.yaml`](k8s/cockroachdb-service.yaml:1)
kubectl apply -f [`k8s/cockroachdb-statefulset.yaml`](k8s/cockroachdb-statefulset.yaml:1)
kubectl -n shisha rollout status sts/cockroachdb --watch
kubectl -n shisha get pvc
```
- Optional: Migrations/Initialisierung (Job) nur ausführen, wenn DB bereit ist:
```bash
kubectl apply -f [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
kubectl -n shisha wait --for=condition=complete job/migrations --timeout=120s
```

3) Backend
- Backend‑Deployment + Service + Config (Env‑Vars für DB) anwenden:
```bash
kubectl apply -f [`k8s/backend-configmap.yaml`](k8s/backend-configmap.yaml:1)
kubectl apply -f [`k8s/backend-deployment.yaml`](k8s/backend-deployment.yaml:1)
kubectl apply -f [`k8s/backend-service.yaml`](k8s/backend-service.yaml:1)
kubectl -n shisha rollout status deploy/shisha-backend --watch
```
- Prüfen: Liveness/Readiness Endpunkte:
```bash
kubectl -n shisha exec $(kubectl -n shisha get pod -l app=shisha-backend -o jsonpath='{.items[0].metadata.name}') -- curl -sS http://localhost:8080/api/healthz
```

4) Frontend
- Frontend‑Deployment + Service + Ingress anwenden:
```bash
kubectl apply -f [`k8s/frontend-deployment.yaml`](k8s/frontend-deployment.yaml:1)
kubectl apply -f [`k8s/frontend-service.yaml`](k8s/frontend-service.yaml:1)
kubectl apply -f [`k8s/ingress.yaml`](k8s/ingress.yaml:1)   # falls Ingress verwendet wird
kubectl -n shisha rollout status deploy/shisha-frontend --watch
```

5) Verifikation
- Dienste prüfen:
```bash
kubectl -n shisha get pods,svc,ingress
# Backend-API testen (falls Service NodePort/ClusterIP + port-forward)
kubectl -n shisha port-forward svc/shisha-backend 8080:8080 &
curl -sS http://localhost:8080/api/healthz
curl -sS http://localhost:8080/api/shishas
```

Tipps / Reihenfolge‑Rationale
- Datenbank zuerst: Backend hängt von der DB‑Verbindung ab; wenn DB nicht verfügbar ist, bleiben Backend‑Pods in Restart/Crashloop.
- Migrationen nach erreichbarer DB: Führe Migrationsjobs erst aus, wenn die StatefulSet‑Pods READY sind.
- Backend vor Frontend: Frontend ist in der Regel nur UI; es erwartet eine erreichbare API. Wenn Backend noch down ist, wird die UI fehlschlagen.
- Secrets & Configs vorher erstellen: damit Deployments beim Start die richtigen ENV‑Variablen lesen.
- Warte‑/Rollback‑Befehle: verwende `kubectl rollout status` und `kubectl rollout undo` für Deployments.

Beispiel‑Reihenfolge (Kurzfassung)
1. [`k8s/namespace.yaml`](k8s/namespace.yaml:1)  
2. [`k8s/secrets.yaml`](k8s/secrets.yaml:1)  
3. [`k8s/cockroachdb-statefulset.yaml`](k8s/cockroachdb-statefulset.yaml:1) + Service  
4. [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1) (optional)  
5. [`k8s/backend-deployment.yaml`](k8s/backend-deployment.yaml:1) + Service  
6. [`k8s/frontend-deployment.yaml`](k8s/frontend-deployment.yaml:1) + Service + [`k8s/ingress.yaml`](k8s/ingress.yaml:1)


## Recent changes

Committed and pushed to remote: `8b00487`  
Commit message: chore(k8s): add shisha namespace and align Helm charts with k8s manifests

Files changed:
- [`k8s/namespace.yaml`](k8s/namespace.yaml:1)
- [`charts/backend/values.yaml`](charts/backend/values.yaml:1)
- [`charts/frontend/values.yaml`](charts/frontend/values.yaml:1)
- [`charts/cockroachdb/values.yaml`](charts/cockroachdb/values.yaml:1)
- [`charts/cockroachdb/templates/statefulset.yaml`](charts/cockroachdb/templates/statefulset.yaml:51)

Kurzbeschreibung:
- Namespace `shisha` hinzugefügt.
- Helm-Chart-Defaults (Names, Images, Probes, DB-Service) angepasst, damit gerenderte Templates mit den `k8s/`-Manifests übereinstimmen.
- Änderungen sind committed und gepusht (Branch: main, Commit: `8b00487`).
