#!/bin/sh
# Language: bash-compatible sh
# Sidecar postStart Skript für CouchDB-Cluster-Join
# - Wartet auf lokalen CouchDB-HTTP-Endpunkt /_up
# - Wenn nur Pod mit Ordinal 0 existiert -> keine Aktion (Einzelknoten)
# - Sonst: versucht idempotent, bekannte Peers per /_cluster_setup?action=add_node beizutreten
# - Robust: Retry mit Exponential-Backoff, klare Log-Prefixe
#
# Hinweise:
# - Erwartet folgende Umgebungsvariablen (werden im Pod gesetzt):
#   COUCHDB_USER, COUCHDB_PASSWORD, HOSTNAME, POD_NAMESPACE (NAMESPACE)
# - Headless-Service: couchdb-headless
# - Dieses Skript läuft im Sidecar und darf den Hauptprozess nicht blockieren.

set -eu

LOG_PREFIX="[cluster-manager postStart]"

COUCH_HOST="127.0.0.1"
COUCH_PORT=5984
HEALTH_PATH="/_up"
MEMBERSHIP_PATH="/_membership"
CLUSTER_SETUP_PATH="/_cluster_setup"

: "${COUCHDB_USER:?Need COUCHDB_USER}"
: "${COUCHDB_PASSWORD:?Need COUCHDB_PASSWORD}"
: "${HOSTNAME:?Need HOSTNAME (Pod-Name)}"
: "${POD_NAMESPACE:?Need POD_NAMESPACE}"

# Max Peers to probe (HPA_MAX - 1). Anpassen falls nötig.
MAX_PEERS=5

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

# 1) Warte auf /_up
wait_for_local_up() {
  log "Warte auf lokalen CouchDB /_up ..."
  tries=0
  until _local_curl GET "${HEALTH_PATH}" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 60 ]; then
      log "WARN: Timeout beim Warten auf lokalen CouchDB after ${tries} tries"
      return 1
    fi
    sleep 2
  done
  log "Lokaler CouchDB /_up ist erreichbar."
  return 0
}

# 2) Erzeuge Liste möglicher Peers (hosts) basierend auf StatefulSet-Ordinals
#    Beispiel: couchdb-0.couchdb-headless.shisha.svc.cluster.local
peer_hostname() {
  idx="$1"
  echo "couchdb-${idx}.couchdb-headless.${POD_NAMESPACE}.svc.cluster.local"
}

# 3) Prüfe, ob Cluster bereits mehrere Knoten hat
get_membership() {
  _local_curl GET "${MEMBERSHIP_PATH}" || true
}

# 4) Prüfe, ob ein gegebener node-name bereits in membership vorkommt
membership_contains() {
  node_name="$1"
  get_membership | grep -F "$node_name" >/dev/null 2>&1
}
 
# Hilfsfunktion: Hole Pod IP über K8s API (ServiceAccount Token + CA)
# Argument: Pod-Name (kurz, z.B. couchdb-1)
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
 
# 5) Versuche, Peer hinzuzufügen (idempotent) -- mit DNS- und API-Fallback
attempt_add_node() {
  peer_host="$1"
  peer_node_name="couchdb@${peer_host%%.*}" # couchdb@couchdb-1
  # Prüfen: ist Peer bereits in Membership des lokalen Knotens?
  if membership_contains "$peer_node_name"; then
    log "Peer ${peer_node_name} bereits in Membership, überspringe."
    return 0
  fi
 
  # Wenn DNS für peer_host nicht funktioniert, versuche Pod-IP via K8s API
  if ! getent hosts "$peer_host" >/dev/null 2>&1; then
    peer_short=$(printf '%s' "$peer_host" | cut -d. -f1)
    log "DNS für ${peer_host} nicht auflösbar, versuche Pod-IP via K8s API für ${peer_short}"
    pod_ip="$(get_pod_ip_via_k8s_api "$peer_short" || true)"
    if [ -n "$pod_ip" ]; then
      log "Erhalte IP ${pod_ip} für Pod ${peer_short}, verwende als Ziel"
      peer_host="$pod_ip"
      peer_node_name="couchdb@${peer_short}"
    else
      log "Konnte Pod-IP für ${peer_short} nicht ermitteln, überspringe ${peer_host}."
      return 1
    fi
  fi
 
  log "Versuche, Peer ${peer_host} als Node hinzuzufügen ..."
  payload="$(printf '{"action":"add_node","host":"%s","port":%s,"username":"%s","password":"%s"}' "$peer_host" "$COUCH_PORT" "$COUCHDB_USER" "$COUCHDB_PASSWORD")"
 
  # Retry mit Backoff
  attempt=0
  max_attempts=6
  sleep_sec=2
  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    resp=$(_local_curl POST "${CLUSTER_SETUP_PATH}" "$payload" 2>/dev/null || true)
    # Prüfe Membership erneut
    if membership_contains "$peer_node_name"; then
      log "Peer ${peer_node_name} erfolgreich hinzugefügt (oder bereits vorhanden)."
      return 0
    fi
    log "Add_node attempt ${attempt} für ${peer_host} fehlgeschlagen, retry in ${sleep_sec}s. Response: ${resp}"
    sleep "$sleep_sec"
    sleep_sec=$((sleep_sec * 2))
  done
 
  log "ERROR: Konnte Peer ${peer_host} nach ${max_attempts} Versuchen nicht hinzufügen."
  return 1
}

main() {
  if ! wait_for_local_up; then
    log "Abbruch: lokaler CouchDB nicht erreichbar."
    exit 1
  fi

  # Wenn dies der Ordinal 0 ist, und keine weiteren Peers resolvbar sind, dann ist das erste Single-Node-Start
  # HOSTNAME format: couchdb-0
  case "$HOSTNAME" in
    couchdb-0)
      # Prüfe, ob mindestens ein weiterer Pod resolvbar ist
      found_other=0
      i=1
      while [ "$i" -lt "$MAX_PEERS" ]; do
        peer=$(peer_hostname "$i")
        if getent hosts "$peer" >/dev/null 2>&1; then
          found_other=1
          break
        fi
        i=$((i + 1))
      done

      if [ "$found_other" -eq 0 ]; then
        log "Single-node Start (Ordinal 0, keine weiteren Peers). Keine Join-Aktion erforderlich."
        return 0
      fi
      ;;
    *)
      # Nicht couchdb-0: wir sollten versuchen, uns an existierenden Peers zu hängen
      ;;
  esac

  # Scan Peers und versuche Join
  joined_any=0
  for idx in $(seq 0 $((MAX_PEERS - 1))); do
    peer=$(peer_hostname "$idx")
    # Skip self: compare short hostname (e.g. couchdb-1) to HOSTNAME
    peer_short=$(printf '%s' "$peer" | cut -d. -f1)
    if [ "$peer_short" = "$HOSTNAME" ]; then
      continue
    fi
    # Nur Peers, die DNS-resolvable sind
    if getent hosts "$peer" >/dev/null 2>&1; then
      # Versuche, den Peer hinzuzufügen (dieses Verbal wird an lokalen CouchDB gerichtet)
      if attempt_add_node "$peer"; then
        joined_any=1
      fi
    fi
  done

  if [ "$joined_any" -eq 1 ]; then
    log "Cluster-Join Versuche abgeschlossen."
  else
    log "Keine Peers gefunden oder alle Join-Versuche gescheitert."
  fi

  return 0
}

main "$@"