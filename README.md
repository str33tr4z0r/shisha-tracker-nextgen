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

Option A — Ingress (empfohlen, MicroK8s)
```bash
# Ingress manifest anwenden (verwaltet Routen für / und /api/*)
kubectl apply -f k8s/ingress.yaml -n shisha

# MicroK8s nginx-ingress bindet häufig an 127.0.0.1 — für lokalen Zugriff nutze einen Host‑Eintrag:
echo "127.0.0.1 shisha.local" | sudo tee -a /etc/hosts

# Prüfen (vom Host)
curl http://shisha.local/api/healthz
# oder (ohne /etc/hosts)
curl -H "Host: shisha.local" http://127.0.0.1/api/healthz
```

Option B — Service ExternalIP (ältere Methode)
```bash
kubectl patch svc shisha-frontend -n shisha --type='merge' -p '{"spec":{"externalIPs":["10.11.12.13"]}}'
```

Option C — Ingress im LAN (MicroK8s + MetalLB)
```bash
# MetalLB aktivieren und einen freien IP‑Range im LAN wählen, z.B.:
microk8s enable metallb:10.0.10.200-10.0.10.210

# Danach erhält der Ingress ggf. eine EXTERNAL‑IP und ist aus dem LAN erreichbar.
kubectl -n shisha get ingress shisha-ingress -o wide
```

Troubleshooting — Kurzbefehle
```bash
kubectl describe pod <pod-name> -n shisha
kubectl get events -n shisha --sort-by=.metadata.creationTimestamp | tail -n 50
```

## All-in-One Copy paste 

```bash

NAMESPACE=shisha

kubectl apply -f k8s/namespace.yaml
kubectl create secret generic shisha-couchdb-admin -n shisha \
  --from-literal=username=ichbineinadmin \
  --from-literal=password=ichbin1AdminPasswort!
kubectl apply -f k8s/couchdb-storage-class.yaml
kubectl apply -f k8s/couchdb-pv.yaml
kubectl apply -f k8s/couchdb.yaml
kubectl rollout status deployment/shisha-couchdb -n shisha --timeout=120s
kubectl apply -f k8s/backend.yaml
kubectl rollout status deployment/shisha-backend-mock -n shisha --timeout=120s
kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml -n shisha
kubectl apply -f k8s/frontend.yaml -n shisha
kubectl rollout status deployment/shisha-frontend -n shisha --timeout=120s
kubectl apply -f k8s/ingress.yaml -n shisha
#kubectl patch svc shisha-frontend -n shisha --type='merge' -p '{"spec":{"externalIPs":["10.11.12.13"]}}'

#Daten Bank Scalieren Optional
kubectl scale statefulset shisha-couchdb --replicas=5 -n shisha
kubectl rollout status statefulset/shisha-couchdb -n shisha --timeout=300s

#HPA / PDBs / Optionales Monitoring
kubectl apply -f k8s/hpa-backend.yaml -n shisha
kubectl apply -f k8s/hpa-frontend.yaml -n shisha
kubectl apply -f k8s/hpa-couchdb.yaml -n shisha
kubectl apply -f k8s/pdb-backend.yaml -n shisha
kubectl apply -f k8s/pdb-frontend.yaml -n shisha
kubectl apply -f k8s/pdb-couchdb.yaml -n shisha

#Sample Daten Optional 
kubectl apply -f k8s/shisha-sample-data.yaml -n shisha
kubectl logs -l job-name=shisha-sample-data -n shisha --tail=200



kubectl get statefulset,service,pods,pvc,hpa,pdb,jobs -n shisha -o wide

```

Lokales Entwickeln & Debugging
- Mock‑Backend läuft lokal im Compose‑Setup als `backend-mock` auf Port 8081 (siehe [`docker-compose.yml`](docker-compose.yml:1)).
- Frontend dev‑server verwendet einen Proxy, der `/api` an das Mock‑Backend weiterleitet (siehe [`frontend/vite.config.ts`](frontend/vite.config.ts:12)).

Hinweise
- Admin‑Secret Name (plain flow): `shisha-couchdb-admin` (standard in den aktualisierten YAMLs in diesem Repo)
- Backend liest `COUCHDB_URL`, `COUCHDB_DATABASE`, `COUCHDB_USER`, `COUCHDB_PASSWORD` aus Environment/Secrets (siehe [`k8s/backend.yaml`](k8s/backend.yaml:1)).
- Für CI/Produktiv‑Setups: Migrationen als CI‑Schritt oder dedizierten Job ausführen und feste Image‑Tags verwenden.

CouchDB — Initial Deploy & korrektes Skalieren (Empfohlene Reihenfolge)

Ziel: frisches Deploy nutzt die Chart‑Standard‑Replikazahl (standard: 5); Kubernetes verwaltet Skalierung (HPA / manueller Scale). Die Backend‑App verbindet sich immer an den ClusterIP Service `http://shisha-couchdb:5984`.

A) Initialer Deploy (einmalig / erstes Setup)
1. Namespace anlegen
```bash
kubectl apply -f k8s/namespace.yaml
```

2. Admin‑Secret (idempotent, ersetzt Platzhalter)
```bash
kubectl create secret generic shisha-couchdb-admin -n shisha \
  --from-literal=username=<username> \
  --from-literal=password=<password>
```

3. StorageClass (dynamische Provisionierung) — falls ihr dynamische PVCs wollt
```bash
kubectl apply -f k8s/couchdb-storage-class.yaml
```
Hinweis: Für lokale/dev Setups könnt ihr noch ein hostPath PV verwenden (`k8s/couchdb-pv.yaml`) — oder komplett auf die StorageClass vertrauen.

4. CouchDB StatefulSet + Services anwenden
```bash
kubectl apply -f k8s/couchdb.yaml -n shisha
kubectl rollout status statefulset/shisha-couchdb -n shisha --timeout=300s
```
Wichtig: volumeClaimTemplates im StatefulSet verwenden `storageClassName` (siehe `charts/couchdb/values.yaml`).

5. Init / Migration Job ausführen (legt DB + Index an)
```bash
kubectl apply -f k8s/migration-job.yaml -n shisha
kubectl wait --for=condition=complete job/shisha-couchdb-init -n shisha --timeout=120s || true
```

6. Erreichbarkeit prüfen
```bash
kubectl run --rm -n shisha smoke-curl --image=curlimages/curl --restart=Never --attach --command -- \
  sh -c "curl -sS -u '<username>:<password>' http://shisha-couchdb:5984/ ; curl -sS -u '<username>:<password>' http://shisha-couchdb:5984/shisha || true"
```

B) Skalieren (Scale‑Up)
1. Skalieren über Kubernetes
```bash
kubectl scale statefulset shisha-couchdb --replicas=5 -n shisha
kubectl rollout status statefulset/shisha-couchdb -n shisha --timeout=300s
```

2. Prüfen, dass neue PVCs gebunden sind
```bash
kubectl get pvc -n shisha
```

3. Prüfen, dass die Pods laufen
```bash
kubectl get pods -n shisha -o wide
```

4. Prüfen CouchDB‑Cluster‑Membership
```bash
kubectl run --rm -n shisha curl-membership --image=curlimages/curl --restart=Never --attach --command -- \
  sh -c "curl -sS -u '<username>:<password>' http://shisha-couchdb:5984/_membership || true"
```
Hinweis: Auf einem single‑node Kubernetes (z.B. MicroK8s ohne mehrere Worker) meldet CouchDB typischerweise nur eine Node. Auf echten Multi‑Node‑Clustern müssen neue Pods über die CouchDB Cluster‑API (/_cluster_setup) miteinander verbunden werden.

Optional — Manuelles Join eines neuen Pods (falls nötig)
- Wenn neue Pods nicht automatisch zusammenfinden, führe für jeden neuen Pod (z.B. `shisha-couchdb-1`) diese Schritte gegen einen bestehenden Mitglieds‑Node aus (Beispiel):
```bash
# auf control machine / oder im Pod: replace <existing-node> / <new-node> mit Hostnames
curl -X POST -u '<username>:<password>' http://<existing-node>:5984/_cluster_setup -H "Content-Type: application/json" \
  -d '{"action":"enable_cluster","bind_address":"0.0.0.0","username":"<username>","password":"<password>","port":5984,"remote_node":"<new-node>"}'
```
Siehe CouchDB Doku: _cluster_setup für genaue Schritte zur Aufnahme/Verwaltung von Knoten.

C) Downscale (Scale‑Down) — sicher durchführen
1. Entfernen aus dem Cluster sauber durchführen (empfohlen):
   - Nutze CouchDB API um Knoten aus dem Cluster zu entfernen (/_cluster_setup bzw. entsprechende Admin‑API).
   - Warte bis Replikation / Datenverteilung abgeschlossen ist.
2. Kubernetes‑ReplicaCount reduzieren
```bash
kubectl scale statefulset shisha-couchdb --replicas=1 -n shisha
```
3. Prüfen PVC/PV Status und Logs:
```bash
kubectl get pods,pvc -n shisha -o wide
kubectl logs -n shisha pod/shisha-couchdb-0 -c couchdb --tail=200
```
Wichtig: Niemals einfach PVCs löschen, bevor ein Knoten sauber aus dem CouchDB‑Cluster entfernt wurde — sonst droht Datenverlust.

D) Troubleshooting / Hinweise
- Wenn PVCs Pending sind: prüfe StorageClass / vorhandene PVs; lösche alte Pending PVCs damit neue mit StorageClass erstellt werden.
- Bei single‑node Dev‑Setups zeigt _membership meistens nur einen Node — das ist erwartetes Verhalten.
- Backend verwendet `http://shisha-couchdb:5984` (oder `COUCHDB_URL`) — keine code‑seitige Skalierungslogik notwendig.
- Für Production: benutze redundante Storage (RWO) und eine echte Multi‑Node Kubernetes‑Umgebung. Automatisierte Cluster‑Join/Leave‑Schritte sollten per Job oder Operator orchestriert werden.


Dateien (wichtige)
- [`k8s/couchdb.yaml`](k8s/couchdb.yaml:1)
- [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1)
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
- [`k8s/frontend.yaml`](k8s/frontend.yaml:1)
- [`k8s/shisha-sample-data.yaml`](k8s/shisha-sample-data.yaml:1) (optional seed via API)

Ende
