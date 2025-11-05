# Skalierung der CouchDB (shisha namespace)

Kurzbeschreibung
- Dieses Verzeichnis enthält die Kubernetes‑Manifeste für die CouchDB‑StatefulSet‑Installation.
- Ziel dieses Dokuments: sichere, reproduzierbare Schritte zum Horizontal‑Skalieren der Datenbank (StatefulSet).

Wichtige Dateien (Referenzen)
- StatefulSet + interner Service: [`k8s/database/couchdb-statefulset.yaml:1`](k8s/database/couchdb-statefulset.yaml:1)
- Headless Service (Ordinals/DNS): [`k8s/database/couchdb-headless.yaml:1`](k8s/database/couchdb-headless.yaml:1)
- ClusterIP Service (intern, Name `shisha-couchdb`): [`k8s/database/couchdb-service.yaml:1`](k8s/database/couchdb-service.yaml:1)
- Sidecar‑Skripte (postStart / preStop): [`k8s/database/couchdb-scripts-configmap.yaml:1`](k8s/database/couchdb-scripts-configmap.yaml:1)
- PV / Storage: [`k8s/database/couchdb-pv.yaml:1`](k8s/database/couchdb-pv.yaml:1)
- PodDisruptionBudget: [`k8s/pdb/couchdb-pdb.yaml:1`](k8s/pdb/couchdb-pdb.yaml:1)
- Secrets: [`k8s/database/couchdb-secrets.yaml:1`](k8s/database/couchdb-secrets.yaml:1)
- HPA (optional): [`k8s/hpa/couchdb-hpa.yaml:1`](k8s/hpa/couchdb-hpa.yaml:1)

Wichtige Voraussetzungen vor dem Skalieren
- Admin‑Secret (`shisha-couchdb-admin`) muss korrekt sein (Benutzer/Passwort, ERLANG_COOKIE).
- Headless Service vorhanden, damit Pod‑Ordinals resolvbar sind.
- NetworkPolicy erlaubt Erlang/Dist-Ports (4369, 9100–9105) zwischen CouchDB‑Pods.
- Storage: VolumeClaimTemplates sind im StatefulSet persistent; prüfe StorageClass/Provisioner auf dynamisches Provisioning oder verfügbare PVs.

Wichtiger Hinweis: volumeClaimTemplates sind immutable
- Felder in volumeClaimTemplates (z.B. storageClassName) können nicht per `kubectl apply` verändert werden.
- Wenn du die StorageClass ändern musst, folge dem Abschnitt "StorageClass ändern" weiter unten (Recreate‑Flow).

1) Manuelles Scale‑Up (sicherer Standard‑Workflow)
- Kurz: erhöhe replicas und überwache Join‑Prozess (postStart / cluster‑join).
- Beispiel:
```bash
# scale up auf 3 Replicas
kubectl -n shisha scale statefulset couchdb --replicas=3

# prüfe Pods und Status
kubectl -n shisha get pods -l app=couchdb -o wide

# prüfe /_up auf neuem Pod (ersetze admin/Passwort)
kubectl -n shisha exec couchdb-1 -- curl -sS -u "$ADMIN:$PASS" http://127.0.0.1:5984/_up

# prüfe Membership auf einem bestehenden Pod
kubectl -n shisha exec couchdb-0 -- curl -sS -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership
```

Erwartetes Verhalten
- Neue Pods starten mit stabilen Hostnames: couchdb-1.couchdb-headless.shisha.svc.cluster.local, usw.
- Sidecar `postStart.sh` führt idempotente Join‑Schritte aus.
- Pod wird erst Ready, wenn Gate‑Datei (/tmp/couchdb-ready) gesetzt ist.

2) StorageClass ändern (StatefulSet volumeClaimTemplates immutable)
Wenn du die storageClassName in `volumeClaimTemplates` ändern musst (z.B. von `couchdb-storage-class` → `microk8s-hostpath`), benutze diesen Flow — Achtung: Daten gehen verloren, wenn PVCs gelöscht werden. Backup vorher!

Empfohlener Ablauf (non‑destructive Vorbereitung)
1. Backup: sichere wichtige Daten (CouchDB‑Replikation oder CouchDB‑Backup).
2. Scale StatefulSet auf 0 (wartungsmodus):
```bash
kubectl -n shisha scale statefulset couchdb --replicas=0
```
3. Warte, bis alle Pods Terminated sind:
```bash
kubectl -n shisha get pods -l app=couchdb
```
4. Lösche alte PVCs (Achtung: löscht Daten!):
```bash
kubectl -n shisha delete pvc -l app=couchdb
# oder gezielt:
kubectl -n shisha delete pvc couchdb-data-couchdb-0 couchdb-data-couchdb-1
```
5. Apply neues StatefulSet‑Manifest mit geänderter storageClass (siehe [`k8s/database/couchdb-statefulset.yaml:1`](k8s/database/couchdb-statefulset.yaml:1)):
```bash
kubectl -n shisha apply -f k8s/database/couchdb-statefulset.yaml
```
6. Scale wieder hoch:
```bash
kubectl -n shisha scale statefulset couchdb --replicas=3
```
7. Prüfe, dass PVCs neu provisioniert und Bound sind:
```bash
kubectl -n shisha get pvc -o wide
```
8. Prüfe Pods, /_up und /_membership wie oben.

3) Automatisches Scaling mit HPA (optional)
- Nutze HPA v2 (oder passende Metrics Adapter) um StatefulSet zu skalieren.
- Voraussetzungen: Metrics Server oder Prometheus Adapter, HPA manifest: [`k8s/hpa/couchdb-hpa.yaml:1`](k8s/hpa/couchdb-hpa.yaml:1).
- Empfohlene Werte: minReplicas:1, maxReplicas:5, target CPU 60–70%.

4) Sauberes Scale‑Down (kritisch)
- Der `preStop.sh` Sidecar sollte Node sauber aus Membership entfernen.
- Empfohlenes Vorgehen:
```bash
# langsam auf 1 Replica runterfahren
kubectl -n shisha scale statefulset couchdb --replicas=1

# prüfe preStop logs des entfernten Pods (cluster-manager container)
kubectl -n shisha logs couchdb-2 -c cluster-manager --follow

# prüfe membership
kubectl -n shisha exec couchdb-0 -- curl -sS -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership
```
- PDB: [`k8s/pdb/couchdb-pdb.yaml:1`](k8s/pdb/couchdb-pdb.yaml:1) verhindert, dass zu viele Pods gleichzeitig entfernt werden.

5) Quick‑Checks nach Skalierung
- Jeder neue Pod: `/_up` → HTTP 200
- `/ _membership` listet alle Nodes
- Sidecar hat Gate‑Datei gesetzt → Pod ist Ready
- Beispiel:
```bash
kubectl -n shisha exec couchdb-0 -- curl -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership
kubectl -n shisha exec couchdb-1 -- curl -u "$ADMIN:$PASS" http://127.0.0.1:5984/_up
kubectl -n shisha get pods -l app=couchdb -o wide
```

6) Häufige Fehler und Debugging
- PVC Pending → StorageClass hat keinen Provisioner oder PV fehlt. Prüfe [`k8s/database/couchdb-pv.yaml:1`](k8s/database/couchdb-pv.yaml:1) und `kubectl get storageclass`.
- 401 Unauthorized → Secret prüfen: [`k8s/database/couchdb-secrets.yaml:1`](k8s/database/couchdb-secrets.yaml:1).
- Sidecar Skripte nicht ausführbar → ConfigMap defaultMode prüfen: [`k8s/database/couchdb-scripts-configmap.yaml:1`](k8s/database/couchdb-scripts-configmap.yaml:1).
- NetworkPolicy blockiert interne Ports → siehe [`k8s/database/couchdb-networkpolicy.yaml:1`](k8s/database/couchdb-networkpolicy.yaml:1).

7) Backend‑Integration / Migration
- Wenn du PVCs gelöscht oder den StatefulSet‑Recreate‑Flow benutzt hast, gehen Daten verloren.
- Das Backend in diesem Repo steuert Migrationen mit `SKIP_MIGRATIONS`. Wenn `SKIP_MIGRATIONS=true` sind Daten/Design‑Docs nicht automatisch angelegt → 500 Errors.
- Wenn nötig, setze in [`k8s/backend/backend.yaml:1`](k8s/backend/backend.yaml:1) `SKIP_MIGRATIONS=false` und redeploye das Backend:
```bash
kubectl -n shisha apply -f k8s/backend/backend.yaml
kubectl -n shisha rollout restart deployment shisha-backend-mock
```
- Alternative manueller DB‑Anlage:
```bash
kubectl -n shisha exec couchdb-0 -- curl -u "$ADMIN:$PASS" -X PUT http://127.0.0.1:5984/shisha
kubectl -n shisha exec couchdb-0 -- curl -u "$ADMIN:$PASS" -X PUT http://127.0.0.1:5984/_users
```

Rollback / Notfall
- Schnelles Rollback auf 1 Replica:
```bash
kubectl -n shisha scale statefulset couchdb --replicas=1
```
- Wenn Membership inkonsistent: nutze `preStop` logs und CouchDB API zum sauberen Entfernen/Neu‑Hinzufügen der Nodes.

Sicherheit / Backups
- Mache vor destruktiven Aktionen (PVC löschen, Recreate) ein Backup.
- Vermeide Secrets im Git‑Repo; nutze externe Secret‑Stores falls möglich.

Kurzbefehle (Übersicht)
- Manuell skalieren: `kubectl -n shisha scale statefulset couchdb --replicas=3`
- StorageClass ändern (Recreate Flow): siehe Abschnitt "StorageClass ändern"
- HPA anwenden: `kubectl -n shisha apply -f k8s/hpa/couchdb-hpa.yaml`

Support-Info
- Wenn du Logs / Fehler hast: sende Auszüge der betroffenen Pods (Container `couchdb` und `cluster-manager`) und die Ausgabe von `kubectl -n shisha get pvc` und `kubectl -n shisha get storageclass`.