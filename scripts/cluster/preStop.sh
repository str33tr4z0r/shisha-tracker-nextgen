#!/bin/sh
# Sidecar preStop Skript für CouchDB Decommissioning
# - Entfernt den aktuellen Node sauber aus dem CouchDB-Cluster vor Pod-Termination
# - Wartet, bis Membership aktualisiert ist
# - Robust: Retry mit Exponential-Backoff und Timeout
#
# Wichtige Hinweise (Deutsch):
# - Dieses Skript wird im Sidecar ausgeführt und sollte zuverlässig und idempotent sein.
# - Es verwendet die CouchDB HTTP-API; in produktiven Umgebungen TLS/Ingress/ServiceMesh empfehlen.
# - Erfordert Umgebungsvariablen: COUCHDB_USER, COUCHDB_PASSWORD, HOSTNAME, POD_NAMESPACE
# - Entfernt den Node via /_cluster_setup oder falls vorhanden via /_nodes/<node> API.
# - Bei Fehlern wird ein nicht-null Exit-Code erzeugt, damit K8s ggf. neu versucht (preStop wird bis zum Container-Stopp ausgeführt).
set -eu

LOG_PREFIX="[cluster-manager preStop]"

COUCH_HOST="127.0.0.1"
COUCH_PORT=5984
CLUSTER_SETUP_PATH="/_cluster_setup"
NODES_API="/_nodes"
MEMBERSHIP_PATH="/_membership"

: "${COUCHDB_USER:?Need COUCHDB_USER}"
: "${COUCHDB_PASSWORD:?Need COUCHDB_PASSWORD}"
: "${HOSTNAME:?Need HOSTNAME (Pod-Name)}"
: "${POD_NAMESPACE:?Need POD_NAMESPACE}"

# Helper: HTTP call to local CouchDB with admin creds
_local_curl() {
  # $1 = method, $2 = path, $3 = data (optional)
  method="$1"
  path="$2"
  data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" -X "$method" "http://${COUCH_HOST}:${COUCH_PORT}${path}" -H "Content-Type: application/json" -d "$data"
  else
    curl -sS -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" -X "$method" "http://${COUCH_HOST}:${COUCH_PORT}${path}"
  fi
}

log() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") ${LOG_PREFIX} $*"
}

# Liefert den CouchDB Node-Namen im Format couchdb@<podip> oder couchdb@<podname> (Fallback)
# Versucht zuerst POD_IP (Umgebungsvariable), dann K8s API, zuletzt HOSTNAME.
get_pod_ip_via_k8s_api() {
  pod="$1"
  token_file="/var/run/secrets/kubernetes.io/serviceaccount/token"
  ca_file="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  api_host="https://kubernetes.default.svc"
  if [ ! -r "$token_file" ] || [ ! -r "$ca_file" ]; then
    return 1
  fi
  token="$(cat "$token_file")"
  url="$api_host/api/v1/namespaces/${POD_NAMESPACE}/pods/${pod}"
  resp="$(curl -sS --header "Authorization: Bearer $token" --cacert "$ca_file" "$url" 2>/dev/null || true)"
  podip="$(printf '%s' "$resp" | grep -o '"podIP"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*"podIP"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  printf '%s' "$podip"
}

node_name() {
  # Verwende POD_IP wenn gesetzt (wird in StatefulSet gesetzt), sonst versuche K8s API, sonst HOSTNAME
  if [ -n "${POD_IP:-}" ]; then
    echo "couchdb@${POD_IP}"
    return 0
  fi

  # HOSTNAME erwartet z.B. couchdb-1
  pod_short="${HOSTNAME}"
  pod_ip="$(get_pod_ip_via_k8s_api "$pod_short" || true)"
  if [ -n "$pod_ip" ]; then
    echo "couchdb@${pod_ip}"
  else
    echo "couchdb@${HOSTNAME}"
  fi
}

# Prüfe aktuelle Membership
get_membership() {
  _local_curl GET "${MEMBERSHIP_PATH}" || true
}

membership_contains() {
  node="$1"
  get_membership | grep -F "$node" >/dev/null 2>&1
}

# Versuche, Node via _cluster_setup?action=remove_node zu entfernen (idempotent)
attempt_remove_via_cluster_setup() {
  node="$1"
  payload="$(printf '{"action":"remove_node","name":"%s"}' "$node")"

  attempt=0
  max_attempts=6
  sleep_sec=2
  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    log "Versuch ${attempt}: Entferne Node ${node} via ${CLUSTER_SETUP_PATH}"
    resp=$(_local_curl POST "${CLUSTER_SETUP_PATH}" "$payload" 2>/dev/null || true)
    # Prüfe, ob Node in Membership noch enthalten ist
    if ! membership_contains "$node"; then
      log "Node ${node} nicht mehr in Membership (erfolgreich entfernt)."
      return 0
    fi
    log "Remove attempt ${attempt} fehlgeschlagen oder Node noch vorhanden, sleep ${sleep_sec}s. Response: ${resp}"
    sleep "${sleep_sec}"
    sleep_sec=$((sleep_sec * 2))
  done

  log "WARN: Entfernen via ${CLUSTER_SETUP_PATH} nicht erfolgreich nach ${max_attempts} Versuchen."
  return 1
}

# Fallback: Versuche DELETE /_nodes/<node> falls unterstützt
attempt_remove_via_nodes_api() {
  node="$1"
  # URL-escape node falls nötig (einfacher Ersatz)
  node_path="$(printf '%s' "$node" | sed 's/@/%40/g')"
  attempt=0
  max_attempts=4
  sleep_sec=2
  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    log "Fallback ${attempt}: DELETE ${NODES_API}/${node_path}"
    resp=$(_local_curl DELETE "${NODES_API}/${node}" 2>/dev/null || true)
    if ! membership_contains "$node"; then
      log "Node ${node} entfernt via ${NODES_API}."
      return 0
    fi
    log "Fallback attempt ${attempt} fehlgeschlagen, sleep ${sleep_sec}s. Response: ${resp}"
    sleep "${sleep_sec}"
    sleep_sec=$((sleep_sec * 2))
  done

  log "WARN: Entfernen via ${NODES_API} nicht erfolgreich nach ${max_attempts} Versuchen."
  return 1
}

# Warten bis Node nicht mehr in Membership auftaucht (Timeout)
wait_for_removal() {
  node="$1"
  timeout_seconds=120
  interval=5
  waited=0
  while membership_contains "$node"; do
    if [ "$waited" -ge "$timeout_seconds" ]; then
      log "ERROR: Timeout nach ${timeout_seconds}s: Node ${node} immer noch in Membership."
      return 1
    fi
    log "Node ${node} noch in Membership, warte ${interval}s..."
    sleep "$interval"
    waited=$((waited + interval))
  done
  log "Node ${node} nicht mehr in Membership."
  return 0
}

main() {
  node="$(node_name)"
  log "Starte Decommission für ${node}"

  # Wenn der Node gar nicht in Membership ist, nichts tun (idempotent)
  if ! membership_contains "${node}"; then
    log "Node ${node} nicht in Membership — keine Aktion erforderlich."
    exit 0
  fi

  # 1) Versuche Entfernen via _cluster_setup
  if attempt_remove_via_cluster_setup "${node}"; then
    # warte bis entfernt
    if wait_for_removal "${node}"; then
      log "Erfolgreich entfernt via cluster_setup."
      exit 0
    else
      log "WARN: Entfernen via cluster_setup meldete Erfolg, aber Node noch vorhanden."
    fi
  fi

  # 2) Fallback mittels _nodes API
  if attempt_remove_via_nodes_api "${node}"; then
    if wait_for_removal "${node}"; then
      log "Erfolgreich entfernt via nodes API."
      exit 0
    else
      log "WARN: Entfernen via nodes API meldete Erfolg, aber Node noch vorhanden."
    fi
  fi

  # 3) Falls alles fehlschlägt, fail hard damit K8s ggf. wieder retryt oder Admin eingreift
  log "ERROR: Konnte Node ${node} nicht aus Cluster entfernen."
  exit 1
}

main "$@"