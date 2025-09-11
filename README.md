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

Deploy mit k8s‑YAMLs (kubectl) — vereinfachte Reihenfolge

Wenn das Backend‑Image bereits in einer Registry verfügbar ist (z. B. ricardohdc/shisha-tracker-nextgen-backend:latest), kannst du die YAMLs direkt in dieser Reihenfolge anwenden:

1. Namespace
```bash
kubectl apply -f k8s/namespace.yaml
```

2. PocketBase (Service / PVC / Deployment)
```bash
kubectl apply -f k8s/pocketbase.yaml
```

3. Backend (Deployment — enthält jetzt das feste Image in [`k8s/backend.yaml`](k8s/backend.yaml:1))
```bash
kubectl apply -f k8s/backend.yaml
```

4. (Optional) Migration Job — nur falls SQL‑Migrationen für ein legacy SQL‑Backend nötig sind
```bash
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s
kubectl logs -f job/shisha-migrate
```

5. HPA für PocketBase (optional)
```bash
kubectl apply -f k8s/hpa-pocketbase.yaml
```

6. Frontend + ConfigMap
```bash
kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml
kubectl apply -f k8s/frontend.yaml
```

Wichtige Hinweise
- Warum vorher Scale‑0 empfohlen wurde: das Scale‑0‑/Image‑Override‑Pattern schützt, wenn das Image noch nicht im Registry verfügbar ist oder die DB noch nicht bereit ist. Wenn du das Image bereits gepusht oder in dein Cluster geladen hast (z. B. mit kind/minikube/k3d), ist das nicht nötig.
- Image‑Verfügbarkeit:
  - Push ins Registry:
    ```bash
    docker build -t ricardohdc/shisha-tracker-nextgen-backend:latest ./backend
    docker push ricardohdc/shisha-tracker-nextgen-backend:latest
    ```
  - Alternativen für lokale Cluster: `kind load docker-image ...`, `minikube image load ...`, oder `ctr images import` (siehe [`README.md`](README.md:1) für Hinweise).
- Helm vs. YAML: Helm bietet Parameterisierung (`--set image.tag=...`) und ist bequemer für wiederholbare Deploys, die YAML‑Reihenfolge bleibt aber gleich.

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
