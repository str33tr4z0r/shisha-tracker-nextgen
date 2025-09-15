# Shisha Tracker — Kurzanleitung

Kurzbeschreibung
- Shisha Tracker ist eine Webanwendung zum Erfassen, Verwalten und Bewerten von Shisha‑Sessions. Die App besteht aus Frontend und Backend und verwendet CouchDB als Standard‑Speicher für Entwicklung und lokale Setups.

Wichtige Hinweise
- Helm‑spezifische Anweisungen wurden in [`docs/HELM.md`](docs/HELM.md:1) ausgelagert. Verwende Helm nur wenn du Charts/Parameter brauchst.

Detaillierte Reihenfolge für plain‑kubectl k8s‑Manifeste (empfohlen)
- Alle Befehle sollten im Repository‑Root ausgeführt werden; ersetze <namespace> falls nötig.

1. Namespace
```bash
kubectl apply -f k8s/namespace.yaml
```

2. (Optional, empfohlen) CouchDB‑Admin Secret
```bash
kubectl create secret generic shisha-couchdb-admin -n shisha \
  --from-literal=username=<username> \
  --from-literal=password=<password>
```

3. PersistentVolume (Dev only, hostPath)
```bash
kubectl apply -f k8s/couchdb-pv.yaml
```
Hinweis: bei hostPath sicherstellen Pfad auf Node sauber ist.

4. CouchDB (Service / PVC / Deployment)
```bash
kubectl apply -f k8s/couchdb.yaml
kubectl rollout status deployment/shisha-couchdb -n shisha --timeout=120s
```

5. (Optional) Initial seed via API (empfohlen): shisha-sample-data
- Das Repo enthält einen einmaligen Job [`k8s/shisha-sample-data.yaml`](k8s/shisha-sample-data.yaml:1), der die Beispiel‑Geschmäcker über das Backend‑API einfügt.
```bash
kubectl apply -f k8s/shisha-sample-data.yaml -n shisha
kubectl logs -l job-name=shisha-sample-data -n shisha --tail=200
```
Hinweis: Dieses Job nutzt das Backend‑Service [`k8s/backend.yaml`](k8s/backend.yaml:1) als Ziel; stelle sicher, dass das Backend‑Service erreichbar ist (Cluster‑DNS: shisha-backend-mock:8080 bzw. dein Backend Service).

6. Backend (Deployment + Service)
```bash
kubectl apply -f k8s/backend.yaml
kubectl rollout status deployment/shisha-backend-mock -n shisha --timeout=120s
```

7. Frontend ConfigMap (Nginx) — muss vor Frontend angewendet werden
```bash
kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml -n shisha
```

8. Frontend (Deployment + Service)
```bash
kubectl apply -f k8s/frontend.yaml -n shisha
kubectl rollout status deployment/shisha-frontend -n shisha --timeout=120s
```

9. HPA / PDBs / Optionales Monitoring
```bash
# Fuer richtige funktion bitte folgendes vorher ausfuehren
# metrics-server installieren (MicroK8s)
#microk8s enable metrics-server

# Oder: apply upstream manifest (normales K8s)
#kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl apply -f k8s/hpa-backend.yaml
kubectl apply -f k8s/hpa-frontend.yaml
kubectl apply -f k8s/pdb-backend.yaml
kubectl apply -f k8s/pdb-frontend.yaml
```

10. Externe Erreichbarkeit
```bash
kubectl patch svc shisha-frontend -n shisha --type='merge' -p '{"spec":{"externalIPs":["10.11.12.13"]}}'
```

Troubleshooting — Kurzbefehle
```bash
kubectl describe pod <pod-name> -n shisha
kubectl get events -n shisha --sort-by=.metadata.creationTimestamp | tail -n 50
```

## All-in-One Copy paste 

```bash
kubectl apply -f k8s/namespace.yaml
kubectl create secret generic shisha-couchdb-admin -n shisha \
  --from-literal=username=ichbineinadmin \
  --from-literal=password=ichbin1AdminPasswort!
kubectl apply -f k8s/couchdb-pv.yaml
kubectl apply -f k8s/couchdb.yaml
kubectl rollout status deployment/shisha-couchdb -n shisha --timeout=120s
kubectl apply -f k8s/backend.yaml
kubectl rollout status deployment/shisha-backend-mock -n shisha --timeout=120s
kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml -n shisha
kubectl apply -f k8s/frontend.yaml -n shisha
kubectl rollout status deployment/shisha-frontend -n shisha --timeout=120s
kubectl patch svc shisha-frontend -n shisha --type='merge' -p '{"spec":{"externalIPs":["10.11.12.13"]}}'

#HPA / PDBs / Optionales Monitoring
kubectl apply -f k8s/hpa-backend.yaml
kubectl apply -f k8s/hpa-frontend.yaml
kubectl apply -f k8s/pdb-backend.yaml
kubectl apply -f k8s/pdb-frontend.yaml

#Sample Daten Optional 
kubectl apply -f k8s/shisha-sample-data.yaml -n shisha
kubectl logs -l job-name=shisha-sample-data -n shisha --tail=200

kubectl -n shisha get pods -o wide
kubectl -n shisha get ns,pv,pvc,svc -o wide

```

Lokales Entwickeln & Debugging
- Mock‑Backend läuft lokal im Compose‑Setup als `backend-mock` auf Port 8081 (siehe [`docker-compose.yml`](docker-compose.yml:1)).
- Frontend dev‑server verwendet einen Proxy, der `/api` an das Mock‑Backend weiterleitet (siehe [`frontend/vite.config.ts`](frontend/vite.config.ts:12)).

Hinweise
- Admin‑Secret Name (plain flow): `shisha-couchdb-admin` (standard in den aktualisierten YAMLs in diesem Repo)
- Backend liest `COUCHDB_URL`, `COUCHDB_DATABASE`, `COUCHDB_USER`, `COUCHDB_PASSWORD` aus Environment/Secrets (siehe [`k8s/backend.yaml`](k8s/backend.yaml:1)).
- Für CI/Produktiv‑Setups: Migrationen als CI‑Schritt oder dedizierten Job ausführen und feste Image‑Tags verwenden.

Dateien (wichtige)
- [`k8s/couchdb.yaml`](k8s/couchdb.yaml:1)
- [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1)
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
- [`k8s/frontend.yaml`](k8s/frontend.yaml:1)
- [`k8s/shisha-sample-data.yaml`](k8s/shisha-sample-data.yaml:1) (optional seed via API)

Ende
