#!/bin/sh
# Erzeugt ein sicheres ERLANG_COOKIE und legt bzw. updated das Kubernetes-Secret
# shisha-couchdb-admin im Namespace shisha. Ziel: Erlang-Cookie synchron für alle CouchDB-Nodes.
#
# Verwendung:
#  - Vorher ggf. COUCHDB_PASSWORD setzen: export COUCHDB_PASSWORD="MEIN_PASS"
#  - ./scripts/create_erlang_cookie.sh
#
# Hinweise (Deutsch):
#  - Das Script erzeugt ein hex-kodiertes Cookie (64 hex Zeichen). Das ist für Erlang/CouchDB geeignet.
#  - In Produktionsumgebungen: Secret-Werte in einem Secret-Backend (Vault, SealedSecrets, ExternalSecrets) verwalten.
#  - Dieses Script nutzt `openssl` und `kubectl`. Beide müssen installiert und konfiguriert sein.
set -eu

# Konfigurierbare Defaults (Überschreibbar via ENV)
SECRET_NAME="${SECRET_NAME:-shisha-couchdb-admin}"
NAMESPACE="${NAMESPACE:-shisha}"
COUCHDB_USER="${COUCHDB_USER:-shisha_admin}"
COUCHDB_PASSWORD="${COUCHDB_PASSWORD:-REPLACE_WITH_SECURE_PASSWORD}"

# Generiere ein sicheres ERLANG_COOKIE (64 hex Zeichen)
if command -v openssl >/dev/null 2>&1; then
  ERLANG_COOKIE="$(openssl rand -hex 32)"
else
  # Fallback: /dev/urandom -> base64 -> nur alphanumerische Zeichen
  ERLANG_COOKIE="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | cut -c1-64)"
fi

echo "Generiertes ERLANG_COOKIE: ${ERLANG_COOKIE}"
echo "Wende Secret ${SECRET_NAME} im Namespace ${NAMESPACE} an..."

# Erzeuge/aktualisiere das Secret idempotent via kubectl apply
kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
  --from-literal=ERLANG_COOKIE="${ERLANG_COOKIE}" \
  --from-literal=COUCHDB_USER="${COUCHDB_USER}" \
  --from-literal=COUCHDB_PASSWORD="${COUCHDB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '${SECRET_NAME}' angewendet (Namespace: ${NAMESPACE})."
echo "Tipp: Entfernen Sie das Cookie aus Ihrer Shell-History/Logs und verwenden Sie ein Secret-Backend für Produktion."