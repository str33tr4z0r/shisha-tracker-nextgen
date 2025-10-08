#!/bin/sh
# POSIX-safe check script for CouchDB cluster status (uses kubectl)
# Avoids bash-only flags and complex quoting to prevent shell errors in CI/containers.
set -eu

LOG_PREFIX="[cluster-check]"

echo "$LOG_PREFIX starting checks"

get_secret() {
  kubectl -n shisha get secret shisha-couchdb-admin -o jsonpath="$1" 2>/dev/null || true
}

user=$(get_secret "{.data.COUCHDB_USER}" | base64 -d 2>/dev/null || true)
pass=$(get_secret "{.data.COUCHDB_PASSWORD}" | base64 -d 2>/dev/null || true)

if [ -z "$user" ] || [ -z "$pass" ]; then
  echo "$LOG_PREFIX ERROR: COUCHDB credentials not found in secret shisha-couchdb-admin"
  exit 1
fi

creds="$user:$pass"

pods=$(kubectl -n shisha get pods -l app=couchdb -o jsonpath="{.items[*].metadata.name}" || true)
if [ -z "$pods" ]; then
  echo "$LOG_PREFIX No couchdb pods found in namespace shisha"
  exit 1
fi

for pod in $pods; do
  echo
  echo "=== POD: $pod ==="
  ready=$(kubectl -n shisha get pod "$pod" -o jsonpath="{.status.containerStatuses[?(@.name=='couchdb')].ready}" 2>/dev/null || echo "false")
  echo "ready=$ready"

  echo "--- membership ---"
  kubectl -n shisha exec "$pod" -c couchdb -- sh -c "curl -sS -u '$creds' http://127.0.0.1:5984/_membership" || echo "failed to query membership on $pod"

  echo "--- _all_dbs ---"
  kubectl -n shisha exec "$pod" -c couchdb -- sh -c "curl -sS -u '$creds' http://127.0.0.1:5984/_all_dbs" || echo "failed to query _all_dbs on $pod"

  echo "--- shisha DB info ---"
  kubectl -n shisha exec "$pod" -c couchdb -- sh -c "curl -sS -u '$creds' http://127.0.0.1:5984/shisha" || echo "shisha DB missing or failed on $pod"
done

echo
echo "$LOG_PREFIX finished"