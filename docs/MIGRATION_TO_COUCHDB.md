# Migration: PocketBase → CouchDB (Dokumentation)

Kurz: Dieses Dokument fasst die durchgeführten Änderungen zusammen, beschreibt die Reihenfolge zum Deployen per kubectl/Helm, listet die betroffenen Dateien und enthält eine kurze Cleanup‑/PR‑Checkliste.

Zusammenfassung der Änderungen
- PocketBase wurde staged aus aktiven Deployments/Charts entfernt und vollständig in das Verzeichnis `archive/pocketbase/` verschoben.
- CouchDB wurde als neuer Standard‑Storage eingeführt. Backend default: `STORAGE=couchdb`.
- Neue k8s‑Manifeste/Charts für CouchDB und ein Seed‑Job wurden erstellt.
- README.md wurde um eine präzise Reihenfolge für plain‑kubectl Deploys erweitert.

Wichtige Aktionen (bereits erledigt)
- Backend: default STORAGE auf CouchDB gesetzt (`backend/main.go`).
- Storage Adapter & Tests: CouchDB Adapter implementiert und Unit‑Tests erfolgreich ausgeführt (`backend/storage/`).
- Helm: `charts/couchdb/` hinzugefügt; `charts/backend` aktualisiert, um CouchDB Env/Secrets zu nutzen.
- Kubernetes: aktiv genutzte PocketBase Manifeste entfernt; CouchDB Manifeste erstellt:
  - `k8s/couchdb.yaml`
  - `k8s/couchdb-pv.yaml` (hostPath für Dev)
  - `k8s/couchdb-seed-job.yaml`
  - `k8s/backend.yaml` angepasst auf CouchDB Env/Secrets
- Archive: Alle ursprünglichen PocketBase‑Charts/Manifeste/Jobs in `archive/pocketbase/` abgelegt.

Empfohlene Apply‑Reihenfolge (plain kubectl)
1. Namespace
   - [`k8s/namespace.yaml`](k8s/namespace.yaml:1)
2. CouchDB Admin Secret (Name: `shisha-couchdb-admin`)
   - `kubectl create secret generic shisha-couchdb-admin -n <ns> --from-literal=username=<user> --from-literal=password=<pass>`
3. (Dev) PV für CouchDB (hostPath)
   - [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1)
   - Wichtig: Ein PersistentVolume (PV) muss vorhanden sein, bevor das PVC erstellt wird. Die vorhandenen CouchDB‑Manifeste setzen in der PVC kein storageClassName; ohne passenden PV bleibt das PVC im Pending‑Zustand und der Pod kann nicht scheduled werden. Erstelle das PV manuell (Dev, hostPath) mit:
```bash
kubectl apply -f k8s/couchdb-pv.yaml
```
   - Alternative: Nutze eine StorageClass (z. B. microk8s-hostpath) und passe das PVC an, damit die dynamische Provisionierung greift.
4. CouchDB Deployment (Service / PVC / Deployment)
   - [`k8s/couchdb.yaml`](k8s/couchdb.yaml:1)
   - `kubectl rollout status deployment/shisha-couchdb -n <ns>`
5. Seed Job (erst wenn CouchDB Ready)
   - [`k8s/couchdb-seed-job.yaml`](k8s/couchdb-seed-job.yaml:1)
   - `kubectl wait --for=condition=complete job/shisha-couchdb-seed -n <ns> --timeout=120s`
6. Backend
   - [`k8s/backend.yaml`](k8s/backend.yaml:1)
   - `kubectl rollout status deployment/shisha-backend -n <ns>`
7. Frontend: ConfigMap → Deployment
   - [`k8s/shisha-frontend-nginx-configmap.yaml`](k8s/shisha-frontend-nginx-configmap.yaml:1)
   - [`k8s/frontend.yaml`](k8s/frontend.yaml:1)

Beobachtungen / Troubleshooting
- CouchDB persistiert Admin‑Hashes im Datenverzeichnis. Bei hostPath PV: Vor dem Wechsel der Admin‑Credentials unbedingt das Node‑Verzeichnis bereinigen, sonst lehnt CouchDB neue Admin‑Secrets ab.
- Logs können Notices enthalten, wenn `_users` fehlt. Das Anlegen der `_users` DB behebt die noisy notices.
- Seed‑Jobs sind idempotent: `file_exists` auf DB ist normal, wenn DB bereits angelegt wurde.
- Hinweis: Die aktuellen CouchDB‑Manifeste in `k8s/` enthalten kein `metadata.namespace`. Beim Anwenden entweder `kubectl apply -f <file> -n shisha` verwenden oder in den Manifests `metadata: namespace: shisha` hinzufügen, damit Ressourcen im Namespace `shisha` erstellt werden.

Dateien / Bereiche mit PocketBase‑Resten (Archiv)
- `archive/pocketbase/` enthält:
  - `k8s-pocketbase.yaml`, `k8s-pocketbase-token-job.yaml`, `Chart.yaml`, `values.yaml`, `archived-backend-client.go`, templates/...
- Aktive Placeholder:
  - `backend/pocketbase/client.go` (kleiner Placeholder, um Builds nicht zu brechen)
- Sonstige verbleibende Verweise (Dokumentation / README / scripts) wurden aktualisiert auf CouchDB‑Flow, aber es existieren noch referenzielle Erwähnungen in README/archives für Nachvollziehbarkeit.

Cleanup‑/PR‑Checkliste (vor vollständigem Entfernen von PocketBase‑Artefakten)
- [ ] Backend Integration smoke tests erfolgreich (Backend verbindet zu CouchDB, liest/schreibt korrekt).
- [ ] HostPath‑State geprüft/gesäubert (falls hostPath verwendet).
- [ ] Linting für Charts/YAMLs durchlaufen.
- [ ] Entferne `backend/pocketbase/client.go` (Placeholder) sobald Integrationstests grün sind.
- [ ] Optional: Lösche `charts/pocketbase/` und `k8s/pocketbase*.yaml` aus dem aktiven Tree; behalte `archive/pocketbase/` in Repo für Historie.
- [ ] Ergänze Helm NOTES in `charts/couchdb/` mit Hinweisen zu Secret/PV und Cleanup.

Vorgeschlagener Git Commit (Message)
Title:
docs: document CouchDB migration and staged PocketBase archive

Body:
- README: add precise kubectl apply order and notes about CouchDB admin secret + hostPath caveats
- Add `docs/MIGRATION_TO_COUCHDB.md` (this file) summarizing migration steps, files changed and cleanup checklist
- Archive PocketBase manifests under `archive/pocketbase/` and leave placeholder `backend/pocketbase/client.go` until QA passes

Ende.