MIGRATION UND CLUSTER-SETUP FÜR COUCHDB (Kurzreferenz)

Zweck
- Beschreibt empfohlene Abläufe für Initialisierung, Skalierung und sauberes Entfernen von CouchDB-Knoten in Kubernetes.
- Repo enthält zwei Mechanismen: ein idempotentes Init-Job (k8s/couchdb-init-job.yaml) für einmalige Initialisierung und einen Per‑Pod Join (initContainer) für automatisches Scale‑Out.

Initial Deploy (einmalig)
1. Namespace + Secret anlegen
   kubectl apply -f k8s/namespace.yaml
   kubectl create secret generic shisha-couchdb-admin -n shisha --from-literal=username=<user> --from-literal=password=<pw>

2. Storage / PVCs
   kubectl apply -f k8s/couchdb-storage-class.yaml
   kubectl apply -f k8s/couchdb-pv.yaml

3. CouchDB StatefulSet + Services
   kubectl apply -f k8s/couchdb.yaml -n shisha
   kubectl rollout status statefulset/shisha-couchdb -n shisha --timeout=300s

4. (Optional) Init / Migration (idempotent)
   kubectl apply -f k8s/couchdb-init-job.yaml -n shisha
   kubectl wait --for=condition=complete job/shisha-couchdb-init -n shisha --timeout=120s || true

Scale‑Out (empfohlen)
- Scale über Kubernetes:
  kubectl scale statefulset shisha-couchdb --replicas=<N> -n shisha
  kubectl rollout status statefulset/shisha-couchdb -n shisha --timeout=300s
- Repo: Per‑Pod initContainer versucht automatisch add_node / enable/finish wenn nötig.
- Prüfen:
  kubectl run --rm -n shisha curl-membership --image=curlimages/curl --restart=Never --attach --command -- sh -c "curl -sS -u '<user>:<pw>' http://shisha-couchdb:5984/_membership"

Scale‑Down (sicher durchführen)
- Vor Reduktion: entferne Knoten sauber aus dem CouchDB‑Cluster per Admin API (/_cluster_setup oder entsprechende Admin‑API).
- Dann: kubectl scale statefulset shisha-couchdb --replicas=<M> -n shisha

Archivierung alter Migration-Job manifest
- Das Repo enthält historisch `k8s/migration-job.yaml`. Wir empfehlen, legacy Manifeste zu archivieren:
  git mv k8s/migration-job.yaml k8s/migration-job-legacy.yaml
  git commit -m "chore(couchdb): archive legacy migration job"

Hinweise / Best Practices
- Admin‑Secret muss vorhanden sein; Charts parametrisieren Secret‑Name in charts/couchdb/values.yaml.
- ReadinessProbe stellt sicher, dass Pod erst Ready wird, wenn er Mitglied im Cluster ist.
- preStop versucht best‑effort remove_node; für vollständige Sicherheit immer manuell prüfen bevor PVCs gelöscht werden.
- Für Production: erwäge einen CouchDB‑Operator (verwaltet Join/Leave, Backups, Upgrades).