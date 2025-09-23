# CouchDB Bootstrap TODO

Status: snapshot 2025-09-23T21:44:14Z

- [x] Rollback operator manifests und CRDs (erledigt)
- [x] StorageClass/PV binding reparieren (PV erstellt, PVC gebunden)
- [x] Namespace + Secret neu anlegen (Namespace `shisha` & Secret `shisha-couchdb-admin` erstellt)
- [x] Statisches PV + StatefulSet ausrollen (`k8s/couchdb-pv.yaml`, `k8s/couchdb-statefulset.yaml`)
- [-] StatefulSet Bootstrapping: Pod `shisha-couchdb-0` startet, aber CrashLoopBackOff (fehlende System-DB `_users`)
- [-] Init-Job robust machen und deployed (`k8s/couchdb-init-job.yaml`) — Script gepatcht, Job läuft aber wartet auf Coordinator
- [-] Debug/Inspektion: Logs sammeln und PV-Inhalt prüfen (offen)
- [ ] Saubere Reprovision des PV (falls Datenverlust akzeptabel)
- [ ] Init-Job erfolgreich ausführen (erst bei stabilem Pod-0)
- [ ] Scale-Test: Replikate hochskalieren und _membership validieren
- [ ] Refactor: cluster-setup in Pod-0 oder Operator (langfristig)
- [ ] Dokumentation aktualisieren: `docs/couchdb-cluster.md`

Nächste empfohlene Schritte (kurz):
1. PVC/PV sauber reprovisionieren falls inkonsistente Daten:
   kubectl -n shisha delete pvc couchdb-data-shisha-couchdb-0 && kubectl delete pv shisha-couchdb-pv && kubectl -n shisha delete pod shisha-couchdb-0
2. StatefulSet warten bis Pod-0 /_up antwortet, dann Init-Job starten:
   kubectl -n shisha apply -f k8s/couchdb-init-job.yaml
3. Falls Job DNS-Probleme hat, Job-Script prüfen (`k8s/couchdb-init-job.yaml`)

Wichtige Dateien:
- [`k8s/couchdb-init-job.yaml`](k8s/couchdb-init-job.yaml:1)
- [`k8s/couchdb-statefulset.yaml`](k8s/couchdb-statefulset.yaml:1)
- [`k8s/couchdb-pv.yaml`](k8s/couchdb-pv.yaml:1)

Letzter bekannter Pod-Fehler:
- "Missing system database _users" → CouchDB terminiert; Lösung: leeres Datenverzeichnis / Init-Job muss `_users` anlegen.

Kontakt: Fortsetzen morgen mit diesem Repo-Kontext.