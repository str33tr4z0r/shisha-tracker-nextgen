# Shisha Tracker — Kurzanleitung

Kurzbeschreibung
- Shisha Tracker ist eine Webanwendung zum Erfassen, Verwalten und Bewerten von Shisha‑Sessions. Die App besteht aus Frontend, Backend und nutzt PocketBase als Standard‑Speicher für Entwicklung und lokale Setups.

Deploy — Übersicht
- Zwei Optionen zum Deployment:
  - Helm‑Charts (empfohlen für wiederholbare Deployments)
  - Direkte k8s‑Manifeste im Ordner [`k8s/`](k8s/:1)

Deploy mit Helm
1. PocketBase installieren
```bash
helm install shisha-pocketbase charts/pocketbase
```

2. Backend (Image‑Tag setzen in [`charts/backend/values.yaml`](charts/backend/values.yaml:1) oder via --set)
```bash
helm upgrade --install shisha-backend charts/backend --set image.tag=v1.0.0
```

3. Frontend
```bash
helm upgrade --install shisha-frontend charts/frontend --set image.tag=v1.0.0
```

Hinweise
- Relevante Chart‑Dateien: [`charts/pocketbase/Chart.yaml`](charts/pocketbase/Chart.yaml:1), [`charts/backend/Chart.yaml`](charts/backend/Chart.yaml:1), [`charts/frontend/Chart.yaml`](charts/frontend/Chart.yaml:1)
- Bei Helm‑Deploys können Werte per `--set` oder `values.yaml` angepasst werden (z. B. Image‑Tag, Ressourcen).

Deploy mit k8s‑YAMLs (kubectl)
Reihenfolge (empfohlen):

1. Namespace
```bash
kubectl apply -f k8s/namespace.yaml
```

2. PocketBase (Service / PVC / Deployment)
```bash
kubectl apply -f k8s/pocketbase.yaml
```

3. Backend (Deployment, zunächst "disabled" — scale 0 oder Command‑Override)
```bash
kubectl apply -f k8s/backend.yaml
kubectl scale deploy shisha-backend-mock --replicas=0
```

4. (Optional) Migration Job — falls SQL‑Migrationen für ein legacy SQL‑Backend benötigt werden
```bash
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s
kubectl logs -f job/shisha-migrate
```

5. HPA für PocketBase (falls verwendet)
```bash
kubectl apply -f k8s/hpa-pocketbase.yaml
```

6. Frontend + ConfigMap
```bash
kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml
kubectl apply -f k8s/frontend.yaml
```

7. Backend Rollout: Image setzen, override entfernen, hochskalieren
```bash
kubectl set image deploy/shisha-backend-mock backend-mock=ricardohdc/shisha-tracker-nextgen-backend:v1.0.0
kubectl patch deploy shisha-backend-mock --type='json' -p '[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]' || true
kubectl scale deploy shisha-backend-mock --replicas=2
kubectl rollout status deploy/shisha-backend-mock
```

Zusätzliche Hinweise
- Das Backend verwendet standardmäßig PocketBase (STORAGE=pb). Prüfe und setze erforderliche Environment‑Variablen in [`k8s/backend.yaml`](k8s/backend.yaml:1).
- Für CI/Produktiv‑Setups: Migrationen als CI‑Schritt oder dedizierten Job ausführen und feste Image‑Tags verwenden.
- Nützliche Dateien:
  - [`k8s/pocketbase.yaml`](k8s/pocketbase.yaml:1)
  - [`k8s/hpa-pocketbase.yaml`](k8s/hpa-pocketbase.yaml:1)
  - [`k8s/backend.yaml`](k8s/backend.yaml:1)
  - [`k8s/migration-job.yaml`](k8s/migration-job.yaml:1)
  - [`k8s/frontend.yaml`](k8s/frontend.yaml:1)
  - [`charts/backend/values.yaml`](charts/backend/values.yaml:1)
  - [`scripts/DEPLOY_COMMANDS.md`](scripts/DEPLOY_COMMANDS.md:1)

Ende
