# CouchDB Cluster — Anleitung (StatefulSet Variante)

Ziel: Clusterfähige CouchDB‑Installation auf Kubernetes ohne Operator, initial 1 Replica, automatische Skalierung zwischen 2–4.

Voraussetzungen
- Kubernetes Cluster mit dynamischer StorageClass (z.B. "standard").
- metrics-server installiert (für HPA).
- Secret `shisha-couchdb-admin` im Namespace `shisha` mit keys `username` und `password`.
- kubectl Zugriff.

Installationsschritte
1. Namespace anlegen:
   kubectl create namespace shisha

2. Secret anlegen (Beispiel):
   kubectl -n shisha create secret generic shisha-couchdb-admin --from-literal=username=admin --from-literal=password=secret

3. StatefulSet + Headless Service deployen:
   kubectl apply -f k8s/couchdb-statefulset.yaml

4. Seed‑Job ausführen (wartet auf Coordinator pod-0):
   kubectl apply -f k8s/couchdb-seed-job.yaml
   kubectl -n shisha logs job/shisha-couchdb-seed -f

5. HPA (Auto‑Scaling) aktivieren:
   kubectl apply -f k8s/couchdb-hpa.yaml

6. PDB hinzufügen:
   kubectl apply -f k8s/couchdb-pdb.yaml

Betriebshinweise
- Skalierung: HPA skaliert Pods; CouchDB Join wird im postStart durchgeführt. Beim Scale‑Up wartet jedes neues Pod auf pod-0 und führt den Join durch.
- Backup: Verwende CouchDB-Replikation oder regelmäßige snapshots des PVs. Beispiel: Erstelle einen weiteren DB‑Cluster als Backup‑Ziel und richte _replicate Aufgaben ein.
- Rollback: Reduziere replicas schrittweise; entferne Knoten via /_cluster_setup with action "remove_node".
- Troubleshooting:
  - Pod 1 kann nicht joinen: prüfe DNS/Service, Credentials, und dass pod-0 unter shisha-couchdb-0.shisha-couchdb-headless erreichbar ist.
  - PVC Pending: prüfe StorageClass und Nodes.

Limitierungen & Empfehlungen
- Ohne Operator ist das Setup einfacher, aber einige Management‑Aufgaben (rebalancing, upgrades) müssen manuell gehandhabt.
- Für Produktion empfehle ich den Einsatz eines Operators oder eines orchestrierenden Tools, das Rolling‑Upgrades und rebalances unterstützt.
- Teste das Setup in einer Staging‑Umgebung bevor du in Produktion gehst.

Dateien im Repo
- k8s/couchdb-statefulset.yaml — StatefulSet + headless Service + join script
- k8s/couchdb-seed-job.yaml — Seed job, erstellt DB + Index
- k8s/couchdb-hpa.yaml — HPA für 2–4 Replicas
- k8s/couchdb-pdb.yaml — PodDisruptionBudget
