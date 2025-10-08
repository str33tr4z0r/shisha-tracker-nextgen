# Shisha Tracker — Kurzanleitung

# ACHTUNG: Aktuell noch auf microk8s ausgelegt !

Kurzbeschreibung
- Shisha Tracker ist eine Webanwendung zum Erfassen, Verwalten und Bewerten von Shisha‑Sessions. Frontend (Vue) + Backend (Go). CouchDB wird als Standard‑Speicher für Entwicklung verwendet.

Quickstart — Lokale Entwicklung

Option A — Docker Compose (Schnellstart)
- Startet CouchDB, Backend (configured for CouchDB) und Frontend (nginx image).
- Dateien: [`docker-compose.yml`](docker-compose.yml:1)

```bash
# Build & start all services (from repository root)
docker-compose up --build -d
# Check services
docker-compose ps
# Backend health
curl http://localhost:8080/api/healthz
# Frontend (nginx)
curl http://localhost:3000/
```

Option B — Kubernetes / microk8s

Production / Kubernetes
- Helm Charts: [`charts/backend`](charts/backend/Chart.yaml:1), [`charts/frontend`](charts/frontend/Chart.yaml:1), [`charts/couchdb`](charts/couchdb/Chart.yaml:1)
- Empfohlene k8s‑Manifeste für CouchDB (StatefulSet): [`k8s/database/couchdb-statefulset.yaml`](k8s/database/couchdb-statefulset.yaml:1)
- Lightweight single‑node manifest: [`k8s/basic-database/couchdb.yaml`](k8s/basic-database/couchdb.yaml:1)

Secrets & Storage
- Charts/Manifeste erwarten Secret `shisha-couchdb-admin` mit keys: `COUCHDB_USER`, `COUCHDB_PASSWORD`, `ERLANG_COOKIE` (für Cluster). Beispiel siehe [`k8s/backend/backend.yaml`](k8s/backend/backend.yaml:31).

Feld‑Konsistenz (wichtig)
- Frontend erwartet `smokedCount` in UI; CouchDB adapter verwendet `smoked` als Feldname. UI normalisiert beide Varianten (siehe [`frontend/src/App.vue`](frontend/src/App.vue:230)). Empfehlung: vereinheitlichen.
- Ratings: `score` ist integer in Backend (half‑stars×2). Frontend rechnet mit Division durch 2.

Troubleshooting
- CouchDB Index / nextID Probleme:
  - Wenn Adapter bei nextID() auf `no_usable_index` stößt, fällt er zurück auf `_all_docs` (langsam). Stelle sicher, dass der Index existiert: Index wird bei Adapter‑Initialisierung angelegt (siehe [`backend/storage/couchdb_adapter.go`](backend/storage/couchdb_adapter.go:117)).
- Backend startet nicht / env fehlt:
  - Prüfe `DATABASE_*` oder `COUCHDB_*` Umgebungsvariablen.
- Nginx frontend zeigt 502:
  - Prüfe, ob das Backend erreichbar ist (Service/Port) und ob Ingress/ConfigMap korrekt sind (siehe relevante `k8s` Ressourcen).

Backups & Migration
- CouchDB: sichere Daten mit regelmäßigen DB Dumps (curl & couchdb dump tools) oder nutze replication. Für Dev: einfache approach:

```bash
# Export DB to file (example)
curl -sSf -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/shisha/_all_docs?include_docs=true" -o shisha-all.json
```

All-In-One Kubernetes Copy Past Production Deploy für die Shell
```bash

NAMESPACE=shisha
echo "First Steps"
kubectl apply -f k8s/PreStage/namespace.yaml
kubectl create secret generic shisha-couchdb-admin -n "$NAMESPACE" \
  --from-literal=username=shisha_admin \
  --from-literal=password=ichbin1AdminPasswort! \
  --from-literal=ERLANG_COOKIE="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | cut -c1-64)" \
  --from-literal=COUCHDB_USER=shisha_admin \
  --from-literal=COUCHDB_PASSWORD=ichbin1AdminPasswort!

kubectl apply -f k8s/PreStage/couchdb-storageclass.yaml -n "$NAMESPACE"

echo "Database"
kubectl apply -f k8s/database/couchdb-statefulset.yaml -n "$NAMESPACE"
kubectl rollout status statefulset/couchdb -n "$NAMESPACE" --timeout=240s

echo "Backend"
kubectl apply -f k8s/backend/backend.yaml -n "$NAMESPACE"
kubectl rollout status deployment/shisha-backend-mock -n "$NAMESPACE" --timeout=120s

echo "Frontend"
kubectl apply -f k8s/frontend/shisha-frontend-nginx-configmap.yaml -n "$NAMESPACE"
kubectl apply -f k8s/frontend/frontend.yaml -n "$NAMESPACE"
kubectl rollout status deployment shisha-frontend -n "$NAMESPACE" --timeout=120s
kubectl apply -f k8s/frontend/ingress.yaml -n "$NAMESPACE"

echo "scale couchdb"
kubectl scale statefulset couchdb --replicas=3 -n "$NAMESPACE"
echo "sleep 40 seconds"
sleep 40

echo "PostStage (optional) - Datenbank mit Daten fütten"
kubectl apply -f k8s/PostStage/shisha-sample-data.yaml -n "$NAMESPACE"

echo "HPA / PDBs / Optionales Monitoring"
kubectl apply -f k8s/hpa/hpa-backend.yaml -n "$NAMESPACE"
kubectl apply -f k8s/hpa/hpa-frontend.yaml -n "$NAMESPACE"
kubectl apply -f k8s/pdb/pdb-backend.yaml -n "$NAMESPACE"
kubectl apply -f k8s/pdb/pdb-frontend.yaml -n "$NAMESPACE"
kubectl apply -f k8s/hpa/couchdb-hpa.yaml -n "$NAMESPACE"
kubectl apply -f k8s/pdb/couchdb-pdb.yaml -n "$NAMESPACE"

echo 'Final resource check (filtered by name '"$NAMESPACE"')'
kubectl get all -A | grep "$NAMESPACE" || true
kubectl get pvc -A | grep "$NAMESPACE" || true
kubectl get pv | grep "$NAMESPACE" || true


```

In Case of Microk8s: ./scripts/deploy_all_microk8s.sh

CI / Deployment Hinweise
- Verwende feste Image‑Tags in CI (nicht :latest), siehe [`docs/HELM.md`](docs/HELM.md:1).
- Build & Push Backend image: [`scripts/build_and_push_backend.sh`](scripts/build_and_push_backend.sh:1)

Weitere Hinweise
- Proxy: Vite dev server leitet `/api` an `http://localhost:8081` (Mock). Für lokale Tests passe `VITE_API_URL` in `.env` an.
- Wenn du Helm benutzt, setze `env.adminSecretName` in CouchDB Chart values oder erstelle `shisha-couchdb-admin` Secret im Namespace `shisha`.

Kontakt
- Maintainer: Manuel und Ricardo (siehe Footer im Frontend)

Ende

## DB-Check (Frontend "Check DB" Button)

Was der Button prüft:
- GET `/api/db-health` — prüft die Erreichbarkeit des Storage-Backends (ruft intern `storage.Health()` auf; bei CouchDB versucht der Adapter zuerst `/_up`, dann ein einfacher GET `/`). Ergebnis steuert die Anzeige "DB: healthy/unhealthy/unknown".
- GET `/api/db-info` — holt optionale Cluster‑Metadaten wie `{"isCluster": true, "nodes": 3}` (bei CouchDB verwendet der Adapter `/_membership`).

Wichtige Stellen im Code:
- Frontend: [`frontend/src/App.vue`](frontend/src/App.vue:256) — Funktionen `checkDBHealth()`, `fetchDBInfo()` und `refreshDBStatus()` (Button ruft `refreshDBStatus()` auf).
- Backend: [`backend/main.go`](backend/main.go:123) — Handler für `/api/db-health`; [`backend/main.go`](backend/main.go:166) — Handler für `/api/db-info`.
- Storage‑Adapter:
  - CouchDB: [`backend/storage/couchdb_adapter.go`](backend/storage/couchdb_adapter.go:149) — `Health()` und `DBInfo()` (fragt `_up` bzw. `_membership`).
  - GORM/SQL: [`backend/storage/gorm_adapter.go`](backend/storage/gorm_adapter.go:133) — `Health()` und einfache `DBInfo()`-Implementierung.

Kurz: Der Button prüft zuerst Health, danach Cluster‑Info und speichert beides lokal in der UI (`dbHealthy` und `runtimeInfo.dbInfo`).

Schnelltest (lokal, Port‑Forward zum Ingress):
```bash
# Port‑forward zum Ingress‑Controller (Anpassen falls Pod-Name anders)
kubectl -n ingress port-forward pod/nginx-ingress-microk8s-controller-vwcbb 8081:80

# dann im anderen Terminal:
curl -i http://localhost:8081/api/db-health
curl -i http://localhost:8081/api/db-info
```

Hinweis:
- Für `/api/db-info` bzw. `/api/db-health` muss das Backend neu gebaut/deployt sein (neue Handler/Adapter-Methoden wurden hinzugefügt). Wenn die Endpunkte über Ingress aufgerufen werden sollen, stellen Sie sicher, dass die Ingress‑Regeln die Pfade an den Backend‑Service weiterleiten (siehe [`k8s/frontend/ingress.yaml`](k8s/frontend/ingress.yaml:1)).
