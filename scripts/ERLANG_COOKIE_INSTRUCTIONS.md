# ERLANG_COOKIE erstellen und in Kubernetes anwenden (Deutsch)

Kurz: Sie können das ERLANG_COOKIE lokal generieren und als Kubernetes Secret setzen. Im Repo gibt es bereits ein Hilfs-Skript: `scripts/create_erlang_cookie.sh` — alternativ die folgenden Einzeiler/Schritte.

1) Mit dem bereitgestellten Skript (empfohlen, idempotent)
- Setzen Sie ggf. Ihr Admin-Passwort temporär:
  export COUCHDB_PASSWORD="MeinSicheresPasswort"
- Ausführen:
  ./scripts/create_erlang_cookie.sh
  -> Das Skript erzeugt ein sicheres Cookie und wendet das Secret `shisha-couchdb-admin` im Namespace `shisha` an.

2) Einzeilige Erzeugung + kubectl (manuell)
- Generiere Cookie (openssl):
  ERLANG_COOKIE=$(openssl rand -hex 32)
- Erstelle/aktualisiere Secret:
  kubectl -n shisha create secret generic shisha-couchdb-admin \
    --from-literal=ERLANG_COOKIE="${ERLANG_COOKIE}" \
    --from-literal=COUCHDB_USER="shisha_admin" \
    --from-literal=COUCHDB_PASSWORD="ReplaceMe" \
    --dry-run=client -o yaml | kubectl apply -f -

3) Secret prüfen & dekodieren
- Zeige Secret-Rohdaten:
  kubectl -n shisha get secret shisha-couchdb-admin -o yaml
- ERLANG_COOKIE dekodieren:
  kubectl -n shisha get secret shisha-couchdb-admin -o jsonpath='{.data.ERLANG_COOKIE}' | base64 --decode && echo

4) Hinweise / Sicherheit
- ERLANG_COOKIE muss bei allen CouchDB-Nodes identisch sein.
- In Produktion: Verwenden Sie ein Secret-Backend (Vault, ExternalSecrets, SealedSecrets), nicht plain kubectl create.
- Entfernen Sie Cookie/Passwörter aus Shell-History / Logs.
- Wenn Sie CI/CD verwenden: legen Sie das Secret via pipeline Secrets oder Provider ein.

5) Troubleshooting
- Wenn Nodes sich nicht verbinden: prüfen Sie, ob Secret im gleichen Namespace vorhanden ist und korrekt dekodiertes Cookie übereinstimmt.
- Prüfen Sie Pod-Env: kubectl -n shisha exec -it couchdb-0 -- printenv | grep ERLANG_COOKIE

Diese Datei ist eine kurze Anleitung; das Repo-Skript `scripts/create_erlang_cookie.sh` automatisiert die sinnvollen Defaults.