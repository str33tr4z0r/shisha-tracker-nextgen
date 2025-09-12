# Shisha Tracker — Kurzanleitung

Kurzbeschreibung
- Shisha Tracker ist eine Webanwendung zum Erfassen, Verwalten und Bewerten von Shisha‑Sessions. Die App besteht aus Frontend, Backend und nutzt PocketBase als Standard‑Speicher für Entwicklung und lokale Setups.

Deploy — Übersicht
- Zwei Optionen zum Deployment:
  - Helm‑Charts (empfohlen für wiederholbare Deployments)
  - Direkte k8s‑Manifeste im Ordner [`k8s/`](k8s/:1)

Deploy mit Helm (empfohlen)
1. PocketBase installieren
```bash
helm install shisha-pocketbase charts/pocketbase
```
Hinweis zu Token‑Erzeugung:
- Der PocketBase‑Chart kann automatisch einen Admin‑API‑Token anlegen. Standardmäßig ist ein Helm post‑install Hook (Job) aktiviert und erstellt ein Secret mit dem Token (Name: `{{ include "pocketbase.fullname" . }}-token`).
- Alternativ kannst du beim Installieren ein Token per values vorgeben (nicht empfohlen für langlebige Secrets):
  - Setze `token.createFromValues=true` und `token.value=<token>` in [`charts/pocketbase/values.yaml`](charts/pocketbase/values.yaml:1).
- Wenn du nichts änderst, erzeugt Helm bei Installation das Admin‑Secret und der Hook erstellt das Token‑Secret automatisch (sofern der Cluster Jobs ausführen darf).

2. Backend (Image‑Tag setzen in [`charts/backend/values.yaml`](charts/backend/values.yaml:1) oder via --set)
```bash
helm upgrade --install shisha-backend charts/backend --set image.tag=latest
```

3. Frontend
```bash
helm upgrade --install shisha-frontend charts/frontend --set image.tag=latest
```

Wichtige Chart‑Dateien
- [`charts/pocketbase/Chart.yaml`](charts/pocketbase/Chart.yaml:1)
- [`charts/pocketbase/templates/token-create-job.yaml`](charts/pocketbase/templates/token-create-job.yaml:1) (Helm Hook: erstellt Token‑Secret)
- [`charts/pocketbase/templates/secret-admin.yaml`](charts/pocketbase/templates/secret-admin.yaml:1) (Admin‑Creds; wird vom Chart gerendert)
- [`charts/pocketbase/templates/secret-token.yaml`](charts/pocketbase/templates/secret-token.yaml:1) (falls `token.createFromValues=true`)
- [`charts/backend/Chart.yaml`](charts/backend/Chart.yaml:1)
- [`charts/frontend/Chart.yaml`](charts/frontend/Chart.yaml:1)
- Bei Helm‑Deploys können Werte per `--set` oder `values.yaml` angepasst werden (z. B. Image‑Tag, Ressourcen).

Deploy mit k8s‑YAMLs (kubectl) — vereinfachte Reihenfolge

Wenn das Backend‑Image bereits in einer Registry verfügbar ist (z. B. ricardohdc/shisha-tracker-nextgen-backend:latest), kannst du die YAMLs direkt in dieser Reihenfolge anwenden. Zusätzlich ist ein Token‑Erzeugungs‑Job verfügbar, wenn du nicht mit Helm arbeitest.

Empfohlene Reihenfolge (plain kubectl)
1. Namespace
```bash
kubectl apply -f k8s/namespace.yaml
```

2. (Optional aber empfohlen) Admin‑Secret für PocketBase erstellen
- Ersetze <email> und <password> durch gewünschte Admin‑Zugangsdaten. Der Name muss `shisha-pocketbase-admin` lauten (used by plain Job).
```bash
kubectl create secret generic shisha-pocketbase-admin -n shisha \
  --from-literal=email=admin@example.com \
  --from-literal=password=changeme
```

3. PocketBase (Service / PVC / Deployment)
```bash
kubectl apply -f k8s/pocketbase.yaml
```

4. (Plain‑K8s) Token‑Erzeugungs‑Job ausführen (wenn du ein Token‑Secret willst)
- Dieser Job wartet auf PocketBase, authentifiziert sich mit dem Admin‑Secret und legt `shisha-pocketbase-token` an.
```bash
kubectl apply -f k8s/pocketbase-token-job.yaml
kubectl wait --for=condition=complete job/shisha-pocketbase-token-create -n shisha --timeout=120s
kubectl get secret shisha-pocketbase-token -n shisha -o yaml
```
- Alternativ kannst du das Token manuell erzeugen und als Secret anlegen:
```bash
# Beispiel: Token in $TOKEN speichern, dann
kubectl create secret generic shisha-pocketbase-token -n shisha --from-literal=token="$TOKEN"
```

5. Backend (Deployment — enthält jetzt das Referenz auf Token‑Secret fallback zu Admin‑Creds)
```bash
kubectl apply -f k8s/backend.yaml
```

6. (Optional) Migration Job — nur falls SQL‑Migrationen für ein legacy SQL‑Backend nötig sind
```bash
kubectl apply -f k8s/migration-job.yaml
kubectl wait --for=condition=complete job/shisha-migrate --timeout=120s
kubectl logs -f job/shisha-migrate
```

7. HPA / Frontend / PDBs: apply wie benötigt
```bash
kubectl apply -f k8s/hpa-pocketbase.yaml        # optional
kubectl apply -f k8s/shisha-frontend-nginx-configmap.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/hpa-backend.yaml
kubectl apply -f k8s/hpa-frontend.yaml
kubectl apply -f k8s/pdb-backend.yaml
kubectl apply -f k8s/pdb-frontend.yaml
```

Hinweise (plain kubectl)
- Der plain Job manifest ist: [`k8s/pocketbase-token-job.yaml`](k8s/pocketbase-token-job.yaml:1)
- Admin‑Secret Name (plain flow): `shisha-pocketbase-admin`
- Token‑Secret Name (plain flow): `shisha-pocketbase-token`
- Backend liest bevorzugt `POCKETBASE_TOKEN` aus dem Token‑Secret; falls nicht vorhanden, nutzt es `POCKETBASE_ADMIN_EMAIL` / `POCKETBASE_ADMIN_PASSWORD` (siehe Chart‑Deployment).

Wichtige Hinweise
- Warum vorher Scale‑0 empfohlen wurde: das Scale‑0‑/Image‑Override‑Pattern schützt, wenn das Image noch nicht im Registry verfügbar ist oder die DB noch nicht bereit ist. Wenn du das Image bereits gepusht oder in dein Cluster geladen hast (z. B. mit kind/minikube/k3d), ist das nicht nötig.
- Image‑Verfügbarkeit:
  - Push ins Registry:
    ```bash
    docker build -t ricardohdc/shisha-tracker-nextgen-backend:latest ./backend
    docker push ricardohdc/shisha-tracker-nextgen-backend:latest
    ```
  - Alternativen für lokale Cluster: `kind load docker-image ...`, `minikube image load ...`, oder `ctr images import` (siehe [`README.md`](README.md:1) für Hinweise).
  - GHCR (GitHub Container Registry) Hinweis — Auth nötig:
    Wenn du Images aus ghcr.io ziehen möchtest, musst du dich bei GitHub anmelden und einen Personal Access Token (PAT) mit dem Scope `read:packages` erstellen. Ablauf kurz:
      1. Melde dich bei GitHub an und erstelle einen PAT: Settings → Developer settings → Personal access tokens → Generate new token (classic). Wähle mindestens `read:packages`.
      2. Erstelle ein Kubernetes ImagePullSecret in deinem Cluster (microk8s-Beispiel). Ersetze `<GITHUB_USER>`, `<PERSONAL_ACCESS_TOKEN>`, `<EMAIL>`:
      
      ```bash
      # Erstelle Secret für GHCR (normales Kubernetes)
      kubectl create secret docker-registry ghcr-secret \
        --docker-server=ghcr.io \
        --docker-username=<GITHUB_USER> \
        --docker-password=<PERSONAL_ACCESS_TOKEN> \
        --docker-email=<EMAIL>
      
      # Patch default ServiceAccount, damit Pods das Secret nutzen
      kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr-secret"}]}'
      
      # Anschließend Pods neu erzeugen, damit das Secret beim ImagePull verwendet wird
      kubectl delete pod -l app=shisha-pocketbase
      ```
      
      3. Prüfe den Pod‑Status und Events:
      ```bash
      kubectl get pods -l app=shisha-pocketbase -o wide
      kubectl describe pod <pod-name>
      kubectl get events --sort-by=.metadata.creationTimestamp | tail -n 50
      ```
      
      Hinweis: In deiner lokalen microk8s‑Umgebung musst du die Befehle mit dem Prefix `microk8s.` ausführen (z. B. `microk8s.kubectl create secret ...`). Dateien mit Image/Secrets: siehe [`k8s/pocketbase.yaml`](k8s/pocketbase.yaml:27) (enthält jetzt `imagePullSecrets` falls aktiviert).
- Helm vs. YAML: Helm bietet Parameterisierung (`--set image.tag=...`) und ist bequemer für wiederholbare Deploys, die YAML‑Reihenfolge bleibt aber gleich.

Beschreibungen der wichtigsten k8s‑YAMLs (neu / aktualisiert)
- [`k8s/pocketbase.yaml`](k8s/pocketbase.yaml:1)
  - Stellt PocketBase als Service + Deployment mit PVC bereit. PocketBase ist der Standard‑Speicher (STORAGE=pb) für lokale/Dev‑Setups.
- [`k8s/hpa-pocketbase.yaml`](k8s/hpa-pocketbase.yaml:1)
  - Optionaler HorizontalPodAutoscaler für PocketBase (min/max Replicas); nur anwenden, wenn dein Cluster Metrics API (metrics-server / custom metrics) bereitstellt.
- [`k8s/backend.yaml`](k8s/backend.yaml:1)
  - Backend‑Deployment und Service. Änderungen: replicas wurden auf den HPA‑Minimalwert gesetzt, Ressourcen (requests/limits) hinzugefügt und eine preferred podAntiAffinity, damit Pods über Nodes verteilt werden. Liveness/Readiness‑Probes sind vorhanden.
- [`k8s/hpa-backend.yaml`](k8s/hpa-backend.yaml:1)
  - HPA für das Backend (z. B. minReplicas: 2, maxReplicas: 6). Skaliert anhand CPU‑Utilization; benötigt korrekte Ressourcen‑Requests in der Deployment‑Spec.
- [`k8s/frontend.yaml`](k8s/frontend.yaml:1)
  - Frontend‑Deployment + Service. Änderungen: replicas auf HPA‑min gesetzt, Ressourcen ergänzt und podAntiAffinity. Nginx‑Config kommt aus der ConfigMap [`k8s/shisha-frontend-nginx-configmap.yaml`](k8s/shisha-frontend-nginx-configmap.yaml:1).
- [`k8s/hpa-frontend.yaml`](k8s/hpa-frontend.yaml:1)
  - HPA für das Frontend (z. B. minReplicas: 3, maxReplicas: 5).
- [`k8s/pdb-backend.yaml`](k8s/pdb-backend.yaml:1) und [`k8s/pdb-frontend.yaml`](k8s/pdb-frontend.yaml:1)
  - PodDisruptionBudgets, die während geplanten Wartungen/Upgrades Mindestanzahl an Pods sicherstellen (minAvailable). Werte sind konservativ gewählt; passe sie an die Anzahl deiner Nodes / SLA an.

Empfehlungen für produktive Setups
- Setze Ressourcen (requests/limits) realistisch basierend auf Load‑Tests — HPA funktioniert nur zuverlässig mit Requests.
- Verwende feste Image‑Tags in CI/CD (keine :latest) und pushe Images vor dem Apply.
- Passe PDBs und minReplicas an Clustergröße/SLAs an.
- Stelle sicher, dass ein metrics‑server (oder ein entsprechender Adapter) im Cluster läuft, damit HPA Metriken nutzen kann.

Deploy‑Beispiel (empfohlene Reihenfolge)
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/pocketbase.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/hpa-backend.yaml
kubectl apply -f k8s/hpa-frontend.yaml
kubectl apply -f k8s/pdb-backend.yaml
kubectl apply -f k8s/pdb-frontend.yaml
kubectl apply -f k8s/hpa-pocketbase.yaml  # optional
```

Zusätzliche Hinweise
- Das Backend verwendet standardmäßig PocketBase (STORAGE=pb). Prüfe und setze erforderliche Environment‑Variablen in [`k8s/backend.yaml`](k8s/backend.yaml:1).
- Für CI/Produktiv‑Setups: Migrationen als CI‑Schritt oder dedizierten Job ausführen und feste Image‑Tags verwenden.
- Nützliche Dateien:
  - [`k8s/pocketbase.yaml`](k8s/pocketbase.yaml:1)
  - [`k8s/hpa-pocketbase.yaml`](k8s/hpa-pocketbase.yaml:1)
  - [`k8s/backend.yaml`](k8s/backend.yaml:1)
  - [`k8s/hpa-backend.yaml`](k8s/hpa-backend.yaml:1)
  - [`k8s/frontend.yaml`](k8s/frontend.yaml:1)
  - [`k8s/hpa-frontend.yaml`](k8s/hpa-frontend.yaml:1)
  - [`k8s/pdb-backend.yaml`](k8s/pdb-backend.yaml:1)
  - [`k8s/pdb-frontend.yaml`](k8s/pdb-frontend.yaml:1)
  - [`k8s/shisha-frontend-nginx-configmap.yaml`](k8s/shisha-frontend-nginx-configmap.yaml:1)
  - [`charts/backend/values.yaml`](charts/backend/values.yaml:1)
  - [`scripts/DEPLOY_COMMANDS.md`](scripts/DEPLOY_COMMANDS.md:1)
  
Ende

## Externer Zugriff auf das Frontend (ClusterIP → externe IP / LoadBalancer / lokale Workarounds)

Nach der Standard‑Deployment‑Konfiguration wird das Frontend als ClusterIP‑Service angelegt (siehe [`k8s/frontend.yaml`](k8s/frontend.yaml:70) bzw. das Chart‑Template [`charts/frontend/templates/service.yaml`](charts/frontend/templates/service.yaml:8)). Für externen Zugriff außerhalb des Clusters gibt es drei sinnvolle Optionen:

### Option A — ClusterIP + externalIPs (on‑prem, Router/Firewall konfigurierbar)
Wenn dein Infrastruktur‑/Netzwerk‑Team eine externe IP auf einem Node routen kann, kannst du sie dem Service als externalIP hinzufügen.

Beispiel (Patch, Namespace optional):
```bash
kubectl patch svc shisha-frontend -n <namespace> --type='merge' -p '{"spec":{"externalIPs":["203.0.113.10"]}}'
```

Alternativ den Service in YAML ändern (Beispielauszug):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: shisha-frontend
spec:
  type: ClusterIP
  externalIPs:
    - 203.0.113.10
  ports:
    - name: http
      port: 80
      targetPort: 80
```
Wichtig: Die IP muss auf Cluster‑Nodes routbar sein und die Nodes müssen den Traffic an den Service weiterleiten. Nutze diese Option nur, wenn du Kontrolle über das Layer‑3‑Routing hast.

### Option B — LoadBalancer (empfohlen für produktive Setups mit externem IP‑Pool, z.B. MetalLB)
Auf lokalen/on‑prem‑Clustern ohne Cloud‑LB kannst du MetalLB installieren und einen IP‑Pool bereitstellen. Danach den Service als LoadBalancer ausrollen (bei Helm: `--set service.type=LoadBalancer` wie im Chart‑Template).

MetalLB installieren (Beispiel):
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
```

Beispiel für MetalLB AddressPool (speichere als `metallb-config.yaml` und `kubectl apply -f metallb-config.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: shisha-ip-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.0.2.240-192.0.2.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: shisha-l2
  namespace: metallb-system
spec: {}
```

Dann das Frontend per Helm als LoadBalancer deployen:
```bash
helm upgrade --install shisha-frontend charts/frontend --set service.type=LoadBalancer --set image.tag=latest
```

Referenz für das Service‑Template: [`charts/frontend/templates/service.yaml`](charts/frontend/templates/service.yaml:8)

### Option C — Lokale Workarounds (minikube, port‑forward, NodePort)
Für Development oder wenn keine externe IP verfügbar ist:

- minikube:
```bash
minikube service shisha-frontend -n <namespace> --url
# oder
minikube tunnel   # stellt LoadBalancer IPs zur Verfügung (benötigt sudo)
```

- kubectl port‑forward (schnell, nur lokal):
```bash
kubectl port-forward deployment/shisha-frontend 8080:80 -n <namespace>
# dann im Browser: http://localhost:8080
```

- NodePort (exponiert Service an Node‑Port):
```bash
kubectl patch svc shisha-frontend -n <namespace> --type='merge' -p '{"spec":{"type":"NodePort"}}'
kubectl get svc shisha-frontend -n <namespace>
# öffne http://<node-ip>:<nodePort>
```

Kurzer Hinweis zu Namespace: Ersetze `<namespace>` mit dem Namespace, den du benutzt (oder lasse `-n <namespace>` weg für default). Prüfe nach Änderungen mit:
```bash
kubectl get svc shisha-frontend -n <namespace> -o wide
```

Ende der Ergänzung.
