# API Dokumentation

Diese Datei beschreibt die verfügbaren API‑Endpunkte der Shisha Tracker Anwendung.
Die APIs sind unter dem Präfix /api erreichbar.

Basis: /api

## Wichtigste Endpunkte

### GET /api/info
Liefert Laufzeitinformationen (nützlich für Debugging / Footer).
- Felder: pod, hostname, container_id
- Beispiel (curl):
```bash
curl http://localhost:8081/api/info
```
- Beispielantwort:
```json
{"pod":"mypod-1","hostname":"host123","container_id":"containerabc"}
```
Verweis: Implementierung in [`backend/main.go:127`](backend/main.go:127) bzw. Mock in [`backend/mock/main.go:47`](backend/mock/main.go:47).

### GET /api/healthz
- Healthcheck (200 OK bei Verfügbarkeit)
- Beispiel:
```bash
curl -i http://localhost:8081/api/healthz
```

### GET /api/ready
- Readiness probe (200 OK)

### GET /api/metrics
- Prometheus‑kompatible Metriken (plain text)

## Shisha Ressourcen

### GET /api/shishas
- Liste aller Shishas (inkl. Hersteller, Bewertungen, Kommentare)
- Beispiel:
```bash
curl http://localhost:8081/api/shishas
```
- Antwort: JSON Array von Objekten:
```json
[{"id":1,"name":"Mint Breeze","flavor":"Minze","manufacturer":{"id":1,"name":"Al Fakher"},"ratings":[...],"comments":[...],"smokedCount":0}]
```

### POST /api/shishas
- Erstellt eine neue Shisha.
- Request Body (JSON):
```json
{"name":"My Shisha","flavor":"Geschmack","manufacturer":{"id":0,"name":"Hersteller"}}
```
- Antwort: 201 Created mit dem erstellten Objekt.

### GET /api/shishas/:id
- Einzelne Shisha abrufen.

### PUT /api/shishas/:id
- Shisha aktualisieren (ganze Ressource).

### DELETE /api/shishas/:id
- Shisha löschen (204 No Content).

## Bewertungen & Kommentare

### POST /api/shishas/:id/ratings
- Fügt eine Bewertung hinzu.
- Payload:
```json
{"user":"alice","score":4}
```
- score ist integer (half‑stars × 2). Beispiel: 4 -> 2 Sterne.

### POST /api/shishas/:id/comments
- Fügt einen Kommentar hinzu.
- Payload:
```json
{"user":"bob","message":"Tolles Aroma"}
```

### POST /api/shishas/:id/smoked
- Erhöht den smokedCount um 1. Antwort enthält das neue smokedCount.
- Beispiel:
```bash
curl -X POST http://localhost:8081/api/shishas/1/smoked
```

## Lokales Entwickeln & Debugging

- Mock‑Backend läuft lokal im Compose‑Setup als `backend-mock` auf Port 8081 (siehe [`docker-compose.yml:18`](docker-compose.yml:18)).
- Frontend dev‑server verwendet einen Proxy, der `/api` an das Mock‑Backend weiterleitet (siehe [`frontend/vite.config.ts:12`](frontend/vite.config.ts:12)).
- Quicktests:
```bash
curl http://localhost:8081/api/info   # direkt am Mock
curl http://localhost:3000/api/info   # über Vite‑Proxy (Devserver)
```

## Hinweise

- Für Produktionsdeploy stelle sicher, dass der echte Backend‑Service das /api/info mit geeigneten Feldern liefert oder die Downward API in Kubernetes gesetzt ist.
- Änderungen an der API bitte in den jeweiligen Handlern dokumentieren (Siehe [`backend/main.go:127`](backend/main.go:127) und [`backend/mock/main.go:47`](backend/mock/main.go:47)).

-- Ende --