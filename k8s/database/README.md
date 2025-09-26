# Skalierung der CouchDB (shisha namespace)

Kurzbeschreibung
- Dieses Verzeichnis enthält die Kubernetes‑Manifeste für die CouchDB‑StatefulSet‑Installation.
- Initialer Deploy läuft als Single‑Node StatefulSet (`replicas: 1`) und ist vorbereitet für späteres horizontales Skalieren.

Wichtige Dateien
- StatefulSet + interner Service: [`k8s/database/couchdb-statefulset.yaml:1`](k8s/database/couchdb-statefulset.yaml:1)
- Headless Service (Ordinals/DNS): [`k8s/database/couchdb-headless.yaml:1`](k8s/database/couchdb-headless.yaml:1)
- ClusterIP Service (interner Name `shisha-couchdb`): [`k8s/database/couchdb-service.yaml:1`](k8s/database/couchdb-service.yaml:1)
- Sidecar‑Skripte (postStart / preStop): [`k8s/database/couchdb-scripts-configmap.yaml:1`](k8s/database/couchdb-scripts-configmap.yaml:1) und lokale Kopien: [`scripts/cluster/postStart.sh:1`](scripts/cluster/postStart.sh:1), [`scripts/cluster/preStop.sh:1`](scripts/cluster/preStop.sh:1)
- HPA (optional / CPU): [`k8s/hpa/couchdb-hpa.yaml:1`](k8s/hpa/couchdb-hpa.yaml:1)
- PodDisruptionBudget (minAvailable: 1): [`k8s/pdb/couchdb-pdb.yaml:1`](k8s/pdb/couchdb-pdb.yaml:1)
- Secrets / Credentials: [`k8s/database/couchdb-secrets.yaml:1`](k8s/database/couchdb-secrets.yaml:1)

Wichtige Voraussetzungen vor dem Skalieren
- Admin‑Secret (`shisha-couchdb-admin`) korrekt konfiguriert.
- Headless Service vorhanden, damit DNS Ordinals resolvbar sind.
- NetworkPolicy erlaubt Erlang/Dist-Ports (4369, 9100–9105) zwischen den CouchDB‑Pods.
- Storage: StatefulSet nutzt persistente Volumes; stelle sicher, dass PVs auf allen Nodes verfügbar sind oder ein StorageClass multi‑attach unterstützt.
- Sidecar‑Skripte (`postStart.sh`, `preStop.sh`) in der ConfigMap sind ausführbar (defaultMode=0755).

1) Manuelles Scale‑Up (empfohlen zum Testen)
- Kurz: erhöhe Replicas und überwache Join-Prozess.
```bash
# skaliere auf 3 Replicas
kubectl -n shisha scale statefulset couchdb --replicas=3
# prüfe Pods
kubectl -n shisha get pods -l app=couchdb -o wide
# prüfe lokalen /_up am neuen Pod
kubectl -n shisha exec couchdb-1 -- curl -sS -u "$ADMIN:$PASS" http://127.0.0.1:5984/_up
# prüfe Cluster Membership
kubectl -n shisha exec couchdb-0 -- curl -sS -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership
```

Erwartetes Verhalten
- Neue Pods starten mit stabilen Hostnames: couchdb-1.couchdb-headless.shisha.svc.cluster.local, couchdb-2...
- Sidecar `postStart.sh` wartet auf /_up und führt idempotente Cluster‑Join Schritte aus.
- Pod wird erst Ready, wenn die Gate‑Datei (/tmp/couchdb-ready) gesetzt ist.

2) Automatisches Scaling mit HPA
- Manifest: [`k8s/hpa/couchdb-hpa.yaml:1`](k8s/hpa/couchdb-hpa.yaml:1)
- Empfohlene Basiswerte:
  - minReplicas: 1
  - maxReplicas: 5
  - target CPU utilization: 60–70%
  - scaleDown.behavior.stabilizationWindowSeconds: 600–900
- Voraussetzungen:
  - Metrics Server oder Prometheus Adapter für CPU/Custom Metrics vorhanden.
  - Verwende HPA v2 zur Skalierung von StatefulSets.
- Anwendung:
```bash
kubectl -n shisha apply -f k8s/hpa/couchdb-hpa.yaml
kubectl -n shisha get hpa
```

3) Sauberes Scale‑Down (kritisch)
- preStop Hook + `preStop.sh` entfernen Node sauber aus der Membership bevor Pod terminiert wird.
- Empfohlenes kontrolliertes Herunterskalieren:
```bash
# skalieren auf 1 Replica
kubectl -n shisha scale statefulset couchdb --replicas=1
# logs des entfernten Pods prüfen (cluster-manager container)
kubectl -n shisha logs couchdb-2 -c cluster-manager --follow
# membership prüfen
kubectl -n shisha exec couchdb-0 -- curl -sS -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership
```
- PDB (`k8s/pdb/couchdb-pdb.yaml:1`) verhindert unerwünschtes gleichzeitiges Entfernen mehrerer Pods.

4) Prüfungen nach Skalierung (Quick‑Checks)
- Jeder neue Pod: /_up → HTTP 200
- /_membership listet alle Nodes
- Sidecar hat Gate‑Datei gesetzt → Pod ist Ready
- Beispiel:
```bash
kubectl -n shisha exec couchdb-0 -- curl -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership
kubectl -n shisha exec couchdb-1 -- curl -u "$ADMIN:$PASS" http://127.0.0.1:5984/_up
kubectl -n shisha get pods -l app=couchdb -o wide
```

Fehlerbehebung — typische Ursachen
- DNS/Headless Service nicht korrekt → prüfe [`k8s/database/couchdb-headless.yaml:1`](k8s/database/couchdb-headless.yaml:1) und CoreDNS.
- 401 Unauthorized → Secret prüfen (`k8s/database/couchdb-secrets.yaml:1`).
- Sidecar startet nicht / Skripte nicht ausführbar → ConfigMap defaultMode prüfen (`k8s/database/couchdb-scripts-configmap.yaml:1`).
- NetworkPolicy blockiert Erlang‑Ports → vergleiche mit [`k8s/database/couchdb-networkpolicy.yaml:1`](k8s/database/couchdb-networkpolicy.yaml:1).
- Storage‑Probleme / PV fehlt → prüfe `k8s/database/couchdb-pv.yaml:1` und StorageClass.

Rollback / Notfall
- Schnelles Rollback auf 1 Replica:
```bash
kubectl -n shisha scale statefulset couchdb --replicas=1
```
- Wenn Membership inkonsistent: nutze `preStop` logs und CouchDB API zum sauberen Entfernen der Nodes statt forcierter Pod‑Stops.

Sicherheit / TLS
- Terminiere TLS am Ingress/Proxy oder Service‑Mesh; interne Erlang‑Dist Kommunikation bleibt unverschlüsselt in diesem Setup.
- Secrets nicht im Klartext im Repo ablegen.

Kurzbefehle (Übersicht)
- Manuell skalieren: `kubectl -n shisha scale statefulset couchdb --replicas=3`
- HPA anwenden: `kubectl -n shisha apply -f k8s/hpa/couchdb-hpa.yaml`
- Membership prüfen: `kubectl -n shisha exec couchdb-0 -- curl -u "$ADMIN:$PASS" http://127.0.0.1:5984/_membership`

Support-Info
- Bei konkreten Fehlern (Join‑Fehler, Shard‑Fehler) bitte Log‑Auszüge der betroffenen Pods (CouchDB + cluster-manager) bereitstellen.