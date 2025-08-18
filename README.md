# Shisha Tracker - Architektur & Deployment

Übersicht
Diese Repository enthält ein scaffold für eine Web-Applikation (Frontend: Vue 3 + Tailwind, Backend: Go + Gin + GORM) und Helm-Charts zur Bereitstellung in Kubernetes.

Projektstruktur
- [`frontend`](frontend:1): Vue 3 + Vite + Tailwind
- [`backend`](backend:1): Go (Gin + GORM)
- [`charts`](charts:1): Helm-Charts für frontend, backend und cockroachdb
- [`infra/k8s`](infra/k8s:1): zusätzliche Kubernetes-Infos

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
- Für Backups nutze CockroachDB native Backups oder Velero; Backup-Anleitungen kommen später in [`infra/k8s/backup`](infra/k8s/backup:1).

Debugging / Lokale Entwicklung
- Für lokale Tests kann ein einfaches `docker-compose.yml` genutzt werden (nicht für Produktion). Dieser Inhalt wird später unter [`docker-compose.yml`](docker-compose.yml:1) ergänzt.

Hinweise zum Helm-Chart
- Charts enthalten Platzhalter für Secrets (siehe `values.yaml`), TLS-Keys und imagePullSecrets.
- Standard-Ports: Backend 8080, Frontend 80 (oder 3000 für dev).

Kontakt & Weiteres
- README: Weitere Details, Migrationsskripte und API-Dokumentation folgen in [`backend/README.md`](backend/README.md:1).# shisha-tracker-nextgen
