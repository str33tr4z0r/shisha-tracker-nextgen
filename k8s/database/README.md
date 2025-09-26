# CouchDB Kubernetes Deployment (shisha namespace)

Kurz: Produktionsreife Artefakte für Apache CouchDB als StatefulSet (initial single-node, clusterfähig). Dieses README beschreibt Reihenfolge, Skalierung (up/down), Rollback und Troubleshooting.

Wichtige Dateien (klickbar):
- Namespace: [`k8s/base/namespace.yaml`](k8s/base/namespace.yaml:1)
- Secrets: [`k8s/base/couchdb-secrets.yaml`](k8s/base/couchdb-secrets.yaml:1)
- Config: [`k8s/base/couchdb-config.yaml`](k8s/base/couchdb-config.yaml:1)
- Sidecar-Skripte (ConfigMap): [`k8s/base/couchdb-scripts-configmap.yaml`](k8s/base/couchdb-scripts-configmap.yaml:1)
- Headless Service: [`k8s/base/couchdb-headless.yaml`](k8s/base/couchdb-headless.yaml:1)
- ClusterIP Service: [`k8s/base/couchdb-service.yaml`](k8s/base/couchdb-service.yaml:1)
- StatefulSet + Service: [`k8s/base/couchdb-statefulset.yaml`](k8s/base/couchdb-statefulset.yaml:1)
- PodDisruptionBudget: [`k8s/base/couchdb-pdb.yaml`](k8s/base/couchdb-pdb.yaml:1)
- NetworkPolicy: [`k8s/base/couchdb-networkpolicy.yaml`](k8s/base/couchdb-networkpolicy.yaml:1)
- RBAC: [`k8s/base/couchdb-rbac.yaml`](k8s/base/couchdb-rbac.yaml:1)
- HPA: [`k8s/hpa/couchdb-hpa.yaml`](k8s/hpa/couchdb-hpa.yaml:1)
- Sidecar helper scripts (falls Sie direkt verwenden möchten): [`scripts/cluster/postStart.sh`](scripts/cluster/postStart.sh:1), [`scripts/cluster/preStop.sh`](scripts/cluster/preStop.sh:1)

Vorbedingungen / Hinweise
- Namespace: `shisha` (siehe [`k8s/base/namespace.yaml`](k8s/base/namespace.yaml:1)).
- StorageClass: `sisha-storage-class` (wird im StatefulSet als `storageClassName` verwendet).
- Secret-Name: `shisha-couchdb-admin` enthält COUCHDB_USER, COUCHDB_PASSWORD, ERLANG_COOKIE.
- TLS: TLS-Termination wird nicht hier konfiguriert — empfehle Ingress/ServiceMesh für TLS.

Deploy-Reihenfolge (empfohlen)
1. Namespace erstellen:
   kubectl apply -f k8s/base/namespace.yaml
2. RBAC (ServiceAccount + Role + RoleBinding):
   kubectl apply -f k8s/base/couchdb-rbac.yaml
3. Secrets (ersetzen Sie Platzhalterwerte!):
   kubectl apply -f k8s/base/couchdb-secrets.yaml
4. ConfigMaps (Config + Skripte):
   kubectl apply -f k8s/base/couchdb-config.yaml
   kubectl apply -f k8s/base/couchdb-scripts-configmap.yaml
5. Services:
   kubectl apply -f k8s/base/couchdb-headless.yaml
   kubectl apply -f k8s/base/couchdb-service.yaml
6. StatefulSet (initial replicas:1):
   kubectl apply -f k8s/base/couchdb-statefulset.yaml
7. PodDisruptionBudget & NetworkPolicy:
   kubectl apply -f k8s/base/couchdb-pdb.yaml
   kubectl apply -f k8s/base/couchdb-networkpolicy.yaml
8. HPA (optional aktivieren):
   kubectl apply -f k8s/hpa/couchdb-hpa.yaml

Validierung nach Deploy
- Prüfen, dass Pod exists und ready:
  kubectl -n shisha get pods -l app=couchdb
- Prüfen Health:
  kubectl -n shisha exec -it couchdb-0 -- curl -sSf http://127.0.0.1:5984/_up
- Prüfen Membership (bei mehr Pods):
  kubectl -n shisha exec -it couchdb-0 -- curl -sSf -u $COUCHDB_USER:$COUCHDB_PASSWORD http://127.0.0.1:5984/_membership

Skalieren (manuell)
- Scale up (StatefulSet): kubectl -n shisha scale sts couchdb --replicas=3
  - Neue Pods nutzen Headless-DNS: couchdb-1.couchdb-headless.shisha.svc.cluster.local usw.
  - Sidecar `postStart` versucht idempotent, den Node in das Cluster zu joinen.
- Scale down (StatefulSet): kubectl -n shisha scale sts couchdb --replicas=1
  - Beim Termination des Pods läuft Sidecar `preStop` synchron, entfernt Node sauber aus Cluster (Decommission).
  - PDB minAvailable:1 verhindert, dass gleichzeitig alle Pods entfernt werden.

HPA
- HPA ist CPU-basiert, minReplicas=1, maxReplicas=5, Ziel 70% CPU.
- Verhalten: scaleDown.stabilizationWindowSeconds = 900 (15min) und Policy maximal 1 Pod Reduktion pro 15 Minuten.
- Hinweis: CouchDB-Sharding/Rebalancing muss bei großen Änderungen beachtet werden — planen Sie DB-Rebalancing außerhalb automatischer Skalierung falls nötig.

Rollback / Upgrades
- StatefulSet-Rollout: Kubectl wird RollingUpdate durchführen (Standard für StatefulSet ist RollingUpdate).
- Bei Problemen: prüfen Sie Logs, setzen Sie replicas wieder auf vorige Anzahl: kubectl -n shisha scale sts couchdb --replicas=<old>
- Daten: PVCs sind persistent; prüfen Sie Snapshots/Backups vor Major-Upgrades.

Troubleshooting (häufige Fehler)
- Pod startet, aber /_up fehlt:
  - Logs prüfen: kubectl -n shisha logs couchdb-0 -c couchdb
  - Prüfen, ob Env-Variablen korrekt aus Secret gesetzt sind.
- Node join scheitert nach Scale-up:
  - DNS-Auflösung prüfen: getent hosts couchdb-1.couchdb-headless.shisha.svc.cluster.local
  - Membership überprüfen: GET /_membership auf jedem Knoten
  - Sidecar-Logs prüfen: kubectl -n shisha logs couchdb-1 -c cluster-manager
- Scale-down entfernt nicht sauber:
  - preStop prüft und entfernt Node; bei verbleibenden Membership-Einträgen prüfen, ob preStop Fehler hatte (Logs).
  - Bei Timeout manuell entfernen via Club-API: POST /_cluster_setup?action=remove_node oder DELETE /_nodes/<node>
- PDB blockiert evtl. Wartung: PDB ist bewusst streng (minAvailable:1). Für Wartungsfenster temporär PDB anpassen.

Ports und DNS
- HTTP API: 5984 (intern)
- EPMD: 4369
- Erlang Distribution: 9100-9105 (eingeschränkt via ERL_FLAGS)
- Headless DNS für Pods: couchdb-<ordinal>.couchdb-headless.shisha.svc.cluster.local
- Nodename Format: couchdb@<podname> (z. B. couchdb@couchdb-0)

Sicherheit / TLS
- TLS wird nicht direkt konfiguriert. Empfohlen: TLS am Ingress oder ServiceMesh terminieren.
- ERLANG_COOKIE in Secret muss identisch für alle Nodes sein.

Akzeptanz-Checkliste (manuell prüfbar)
- [ ] replicas=1 → Pod ready, GET /_up 200, keine Join-Versuche im Sidecar-Log
- [ ] Scale up auf 3 → couchdb-1/2 resolvable, /_membership listet alle Nodes
- [ ] Scale down auf 1 → preStop entfernt -2 und -1 sauber, /_membership OK, keine Shard-Fehler
- [ ] PDB verhindert Unterschreitung von 1 Pod
- [ ] NetworkPolicy nur die spezifizierten Ports offen

Weiteres
- Für Produktionsbetrieb: Backup-Strategie, Monitoring (Prometheus-Exporter), Alerting, und Tests des Decommissioning-Prozesses vornehmen.