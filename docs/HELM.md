# Helm — Anleitung

Diese Datei enthält die wichtigsten Helm‑Schritte für das Deployment der Shisha‑Tracker‑Komponenten. Helm ist optional; die standardisierte, plain‑kubectl Reihenfolge bleibt in der Haupt‑README.

Voraussetzungen
- Helm 3.x installiert.
- Arbeitsverzeichnis: Repository‑Root mit den Chart‑Verzeichnissen `charts/`.

CouchDB Chart installieren
```bash
helm install shisha-couchdb charts/couchdb --set env.adminSecretName=shisha-couchdb-admin
```
Hinweis: `adminSecretName` steuert, welches Secret der Chart für Admin‑Credentials verwendet — siehe [`charts/couchdb/values.yaml`](charts/couchdb/values.yaml:1).

Backend installieren / upgrade
```bash
helm upgrade --install shisha-backend charts/backend --set image.tag=latest
```
Wichtige Werte: siehe [`charts/backend/values.yaml`](charts/backend/values.yaml:1).

Frontend installieren / upgrade
```bash
helm upgrade --install shisha-frontend charts/frontend --set image.tag=latest --set service.type=ClusterIP
```

Wichtige Chart‑Parameter (häufig angepasst)
- `env.adminSecretName` — Name des CouchDB‑Admin‑Secrets (Charts/CouchDB).
- `image.tag` — setze feste Image‑Tags in CI/CD.
- `service.type` — ClusterIP / LoadBalancer / NodePort (Frontend).

Template rendern (lokal prüfen)
```bash
helm template charts/backend --values charts/backend/values.yaml
```

Uninstall
```bash
helm uninstall shisha-backend
helm uninstall shisha-frontend
helm uninstall shisha-couchdb
```

CI/CD Hinweise
- Verwende feste Image‑Tags und pushe Images vor `helm upgrade --install`.
- Nutze `--set` oder CI‑values files, niemals `:latest` in produktiven Releases.

Ende