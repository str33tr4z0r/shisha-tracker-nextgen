# Migration: CouchDB Cluster auf IP‑basierte Nodename & local-path Storage

Kurzbeschreibung
- Diese Anleitung beschreibt die Änderungen, die vorgenommen wurden, und wie das aktuelle Setup deployed, bereinigt oder zurückgesetzt werden kann.

Änderungen (Dateien)
- [`k8s/database/couchdb-statefulset.yaml`](k8s/database/couchdb-statefulset.yaml:175) — env POD_IP, COUCHDB_NODENAME="couchdb@$(POD_IP)"; PVCs nutzen `storageClassName: local-path`.
- [`scripts/cluster/postStart.sh`](scripts/cluster/postStart.sh:1) — Join-Logic erweitert: DNS → getent → K8s API → IP‑Fallback.
- [`scripts/cluster/preStop.sh`](scripts/cluster/preStop.sh:1) — node_name() nutzt POD_IP als Fallback.
- [`k8s/database/local-path-provisioner.yaml`](k8s/database/local-path-provisioner.yaml:1) — local-path provisioner manifest (installiert).
- (entfernt) [`k8s/database/hostpath-pv-sc.yaml`](k8s/database/hostpath-pv-sc.yaml:1) und [`k8s/database/couchdb-pv-1.yaml`](k8s/database/couchdb-pv-1.yaml:1) — statische PV/SC entfernt.

Deployment Schritte
1. Installiere local-path provisioner (falls noch nicht installiert):
   kubectl apply -f k8s/database/local-path-provisioner.yaml
2. Optional: Setze local-path als Default:
   kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
3. Deploy/Update StatefulSet:
   kubectl apply -f k8s/database/couchdb-statefulset.yaml
4. Prüfe PVC/PV Bindung:
   kubectl -n shisha get pvc
   kubectl get pv

Hinweise zu PV Cleanup (wenn alte PVs stuck sind)
- Entferne Finalizer falls PV im Terminating hängt:
  kubectl patch pv <pv-name> --type=merge -p '{"metadata":{"finalizers":null}}'
- Dann PV löschen:
  kubectl delete pv <pv-name> --ignore-not-found
- Entferne lokale Manifestdateien aus Git und commit:
  git rm k8s/database/hostpath-pv-sc.yaml k8s/database/couchdb-pv-1.yaml && git commit -m "remove static PV manifests" && git push

Netzwerk / Ports
- CouchDB Erlang‑Distribution verwendet Ports 9100–9105. Stelle sicher, dass die Nodes diese Ports erreichen können.
- NetworkPolicy Datei: [`k8s/database/couchdb-networkpolicy.yaml`](k8s/database/couchdb-networkpolicy.yaml:1)

Cluster Health Checks
- Lokaler /_up:
  kubectl -n shisha exec pod/couchdb-0 -- curl -sS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" http://127.0.0.1:5984/_up
- Cluster membership:
  kubectl -n shisha exec pod/couchdb-0 -- curl -sS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" http://127.0.0.1:5984/_membership
- Prüfe DBs / Shards:
  kubectl -n shisha exec pod/couchdb-0 -- curl -sS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" http://127.0.0.1:5984/_all_dbs

Rollback Schritte
- Setze StatefulSet PVCs zurück auf vorherige storageClass (falls nötig):
  edit `k8s/database/couchdb-statefulset.yaml` volumeClaimTemplates storageClassName: <previous-class>
- Entferne local-path und reapply alte PV-Manifeste falls gewünscht (Achtung: Datenverlust möglich)

Automatisierung / Hinweise
- IP‑basierte Nodename umgehen kurzfristige DNS‑Probleme, führen aber zu IP‑basierter Mitgliedschaft; bei Node‑IP‑Änderungen muss Cluster‑Mitgliedschaft bereinigt werden.
- Für Production: DNS‑basierte Nodename mit stabiler DNS (CoreDNS) oder ein Produktions‑PV‑Provisioner (OpenEBS/Longhorn/NFS) bevorzugen.
- local-path ist für Dev/Single‑Node geeignet; für Production alternative Provisioner verwenden.

Wo sind die Skripte
- Cluster scripts ConfigMap: [`k8s/database/couchdb-scripts-configmap.yaml`](k8s/database/couchdb-scripts-configmap.yaml:1)
- PostStart/PreStop Skripte werden im Sidecar unter /opt/couchdb-scripts gemountet.

ToDo / offengeblieben
- NetworkPolicy prüfen und ggf. anpassen (Ports 9100–9105)
- Monitoring & Health Alerts definieren
- System‑DBs prüfen/erstellen (_users, _replicator, _global_changes)

Kontakt / Hinweise
- Änderungen sind im Branch `feature/ip-couchdb-cluster` gepusht.
- Logs prüfen:
  kubectl -n shisha logs pod/<pod> -c couchdb

End of document