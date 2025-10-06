# Helm — Anleitung (aktualisiert)

Diese Datei beschreibt die empfohlenen Helm‑Befehle für Deployment und lokale Template‑Validierung. Die Projekt‑Manifeste in `k8s/` dienen als Referenz‑Implementierungen; die Charts in `charts/` erzeugen vergleichbare Ressourcen (z. B. StatefulSet für CouchDB).

Voraussetzungen
- Helm 3.x installiert.
- Arbeitsverzeichnis: Repository‑Root mit den Chart‑Verzeichnissen `charts/`.

Wichtig: Secret für CouchDB‑Admin anlegen
Das CouchDB‑Chart erwartet ein Secret mit Admin‑Credentials und dem Erlang‑Cookie. Beispiel:
```bash
kubectl create secret generic shisha-couchdb-admin \
  --from-literal=COUCHDB_USER=admin \
  --from-literal=COUCHDB_PASSWORD=changeme \
  --from-literal=ERLANG_COOKIE=$(head -c 32 /dev/urandom | base64) \
  -n shisha
```
Siehe auch `k8s/database/couchdb-statefulset.yaml` für die vollständige PRODUKTIONS‑Referenz.

CouchDB Chart installieren (StatefulSet, RBAC, Scripts, ConfigMaps)
```bash
helm upgrade --install shisha-couchdb charts/couchdb \
  --namespace shisha \
  --set env.adminSecretName=shisha-couchdb-admin \
  --set serviceAccountName=shisha-couchdb \
  --set persistence.size=5Gi
```
Erläuterung wichtiger Werte (Charts/CouchDB):
- `env.adminSecretName` — Secret mit COUCHDB_USER, COUCHDB_PASSWORD, ERLANG_COOKIE (standard: shisha-couchdb-admin).
- `serviceAccountName` — legt den ServiceAccount für das Chart an (RBAC für Cluster‑Manager).
- `persistence.size` / `persistence.storageClass` — PVC‑Größe und StorageClass (default in Chart: 5Gi).
- `scriptsConfigMapName` / `configMapName` — Namen der ConfigMaps für Cluster‑Manager‑Skripte und CouchDB local.d.

Backend installieren / upgrade
Das Backend wird in den k8s Manifests als `shisha-backend-mock` (Port 8080) geführt; im Chart:
```bash
helm upgrade --install shisha-backend charts/backend \
  --namespace shisha \
  --set image.tag=latest \
  --set env.COUCHDB_URL=http://shisha-couchdb:5984 \
  --set env.COUCHDB_DB=shisha
```
Wichtige Werte: siehe [`charts/backend/values.yaml`](charts/backend/values.yaml:1).

Frontend installieren / upgrade
```bash
helm upgrade --install shisha-frontend charts/frontend \
  --namespace shisha \
  --set image.tag=latest \
  --set service.type=ClusterIP
```
Im k8s Manifest lautet der Service `shisha-frontend` und der Container horcht auf Port 80 (siehe `k8s/frontend/frontend.yaml`).

Template rendern (lokal prüfen)
Zum Überprüfen, welche Ressourcen gerendert werden:
```bash
helm template charts/couchdb --namespace shisha --values charts/couchdb/values.yaml
helm template charts/backend  --namespace shisha --values charts/backend/values.yaml
helm template charts/frontend --namespace shisha --values charts/frontend/values.yaml
```

Uninstall (Namespace `shisha`)
```bash
helm uninstall shisha-backend  -n shisha
helm uninstall shisha-frontend -n shisha
helm uninstall shisha-couchdb -n shisha
```

CI/CD Hinweise
- Verwende feste Image‑Tags, pushe Images vor `helm upgrade --install`.
- Übergib sensible Werte (Secrets, storageClass) über CI‑secrets / values files, nicht via `--set` in Klartext bei produktiven Releases.
- Teste `helm template` im CI als statische Validierung.

Referenzen
- Produktions‑Referenzmanifest: [`k8s/database/couchdb-statefulset.yaml`](k8s/database/couchdb-statefulset.yaml:1)
- Chart‑Defaults: [`charts/couchdb/values.yaml`](charts/couchdb/values.yaml:1)

Ende