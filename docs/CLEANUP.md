# Cleanup — Ressourcen vollständig entfernen

Kurzanleitung, um alle im Repo erzeugten Kubernetes‑Ressourcen rückstandsfrei zu löschen.

Wichtige Hinweise
- Das PV in [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1) hat reclaimPolicy: Retain — Daten bleiben auf dem Node und müssen manuell entfernt werden.
- Lösche Ressourcen in der Reihenfolge unten, um Hänger zu vermeiden.

Vorbereitungen
- Setze Kontext auf das Cluster und Namespace (falls anders):
```bash
kubectl config current-context
kubectl get namespaces
```

1) Entferne optionale Seed-Job / ConfigMap
```bash
kubectl delete -f k8s/couchdb-seed-job-from-configmap.yaml -n shisha || true
kubectl delete configmap shisha-couchdb-seed-config -n shisha || true
kubectl delete job shisha-couchdb-seed -n shisha || true
```

2) Lösche Frontend + Backend
```bash
kubectl delete -f k8s/frontend.yaml -n shisha || true
kubectl delete -f k8s/backend.yaml -n shisha || true
```

3) Lösche CouchDB Deployment & Service (stoppt Pods, PVC bleibt)
```bash
kubectl delete -f k8s/couchdb.yaml -n shisha || true
```

4) Entferne Secrets / ConfigMaps
```bash
kubectl delete secret shisha-couchdb-admin -n shisha || true
kubectl delete configmap shisha-frontend-nginx -n shisha || true
```

5) Entferne PVC und PV
```bash
kubectl delete pvc shisha-couchdb-pvc -n shisha || true
kubectl get pv
# Falls PV noch vorhanden, löschen:
kubectl delete pv shisha-couchdb-pv || true
```

6) Manuelle Entfernung des hostPath (falls benutzt)
- Pfad aus [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1): /var/lib/shisha/couchdb
```bash
# Auf dem Node ausführen (oder per SSH)
sudo rm -rf /var/lib/shisha/couchdb
```

7) Namespace löschen (optional)
```bash
kubectl delete namespace shisha || true
```

8) Prüfen, ob alles weg ist
```bash
kubectl get all -A | grep shisha || true
kubectl get pvc -A | grep shisha || true
kubectl get pv | grep shisha || true
```

Log und Troubleshooting
- Falls PV nicht gelöscht werden kann, prüfe finalizers:
```bash
kubectl get pv shisha-couchdb-pv -o yaml
```

Referenzen
- Deploy‑Manifeste: [`k8s/couchdb.yaml`](k8s/couchdb.yaml:1), [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1)
- Seed‑Manifeste: [`k8s/couchdb-seed-configmap.yaml`](k8s/couchdb-seed-configmap.yaml:1), [`k8s/couchdb-seed-job-from-configmap.yaml`](k8s/couchdb-seed-job-from-configmap.yaml:1)

Ende