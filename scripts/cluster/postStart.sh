#!/bin/sh
# Language: bash-compatible sh
# Sidecar postStart Skript für CouchDB-Cluster-Join (härtet Join/DB-Erstellung und Ghost-Node-Removal)
# - Wartet auf lokalen CouchDB-HTTP-Endpunkt /_up
# - Versucht peers robust hinzuzufügen (wartet auf peer /_up, retries, backoff)
# - Entfernt verwaiste cluster_nodes automatisch
# - Sorgt dafür, dass System-DBs (_users, _replicator) und App-DB (shisha) nach dem Join existieren
# - Setzt Readiness-Gate erst wenn die Voraussetzungen erfüllt sind.
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
MAX_PEERS=10
# Erwartete Cluster-Größe zur erlaubten Erstellung der System-DBs (Replikations-Faktor).
# Kann via Umgebungsvariable überschrieben werden (z.B. in StatefulSet/Helm).
DESIRED_CLUSTER_SIZE=${DESIRED_CLUSTER_SIZE:-3}
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
 
# Wait for a remote peer /_up reachable at http://{ip}:5984/_up
wait_for_peer_up() {
  peer_ip="$1"
  tries=0
  until curl -sS "http://${peer_ip}:5984/_up" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 30 ]; then
      log "WARN: Peer ${peer_ip} nicht erreichbar after ${tries} tries"
      return 1
    fi
    sleep 2
  done
  return 0
}
 
# 2) Erzeuge Liste möglicher Peers (hosts) basierend auf StatefulSet-Ordinals
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
 
# Remove ghost nodes: cluster_nodes entries that are not in all_nodes
remove_ghost_nodes() {
  log "Prüfe auf verwaiste cluster_nodes..."
  memb="$(get_membership || true)"
  # extract arrays
  cluster_nodes=$(printf '%s' "$memb" | grep -o '"cluster_nodes":[^]]*]' | sed 's/^.*\[//;s/\].*$//' | tr -d '" ' || true)
  all_nodes=$(printf '%s' "$memb" | grep -o '"all_nodes":[^]]*]' | sed 's/^.*\[//;s/\].*$//' | tr -d '" ' || true)
  if [ -z "$cluster_nodes" ]; then
    return 0
  fi
  IFS=','; for n in $cluster_nodes; do
    # skip empty
    [ -z "$n" ] && continue
    # if not in all_nodes then remove
    if ! printf '%s' "$all_nodes" | grep -F -q "$n"; then
      log "Gefundener Ghost-Node: $n -> remove_node"
      _local_curl POST "${CLUSTER_SETUP_PATH}" "$(printf '{"action":"remove_node","name":"%s"}' "$n")" >/dev/null 2>&1 || true
    fi
  done
  IFS=' '
}
 
# 5) Versuche, Peer hinzuzufügen (idempotent) -- mit DNS- und API-Fallback und peer-/health-wait
attempt_add_node() {
  peer_host_input="$1"
  peer_ip=""
  peer_node_name=""
 
  # 1) Wenn Input bereits eine IP ist, verwende diese
  if printf '%s' "$peer_host_input" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    peer_ip="$peer_host_input"
    log "Peer Input ist eine IP: ${peer_ip}"
  else
    # 2) Versuche DNS -> extrahiere IP via getent
    host_ip="$(getent hosts "$peer_host_input" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
    if [ -n "$host_ip" ]; then
      peer_ip="$host_ip"
      log "DNS-Auflösung ${peer_host_input} -> ${peer_ip}"
    else
      # 3) Fallback: K8s API nach Pod-IP (verwende kurzen Pod-Namen)
      peer_short=$(printf '%s' "$peer_host_input" | cut -d. -f1)
      log "DNS für ${peer_host_input} nicht auflösbar, versuche Pod-IP via K8s API für ${peer_short}"
      pod_ip="$(get_pod_ip_via_k8s_api "$peer_short" || true)"
      if [ -n "$pod_ip" ]; then
        peer_ip="$pod_ip"
        log "Erhalte IP ${pod_ip} für Pod ${peer_short}, verwende als Ziel"
      else
        log "Konnte Pod-IP für ${peer_short} nicht ermitteln, überspringe ${peer_host_input}."
        return 1
      fi
    fi
  fi
 
  peer_node_name="couchdb@${peer_ip}"
 
  # Prüfen: ist Peer bereits in Membership des lokalen Knotens?
  if membership_contains "$peer_node_name"; then
    log "Peer ${peer_node_name} bereits in Membership, überspringe."
    return 0
  fi
 
  # Warte auf peer /_up bevor add_node aufgerufen wird
  if ! wait_for_peer_up "$peer_ip"; then
    log "Peer ${peer_ip} nicht erreichbar, überspringe add_node."
    return 1
  fi
 
  log "Versuche, Peer ${peer_ip} als Node hinzuzufügen (node name: ${peer_node_name}) ..."
  payload="$(printf '{"action":"add_node","host":"%s","port":%s,"username":"%s","password":"%s"}' "$peer_ip" "$COUCH_PORT" "$COUCHDB_USER" "$COUCHDB_PASSWORD")"
 
  # Retry mit Backoff und tolerante Fehlerbehandlung
  # initial jitter to stagger add_node calls across pods (helpful during scale-ups)
  init_jitter=$(( ( $(date +%s) + $$ ) % 5 ))
  if [ "$init_jitter" -gt 0 ]; then
    log "Initial jitter ${init_jitter}s before add_node for ${peer_ip}"
    sleep "$init_jitter"
  fi

  attempt=0
  max_attempts=12
  sleep_sec=2
  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    resp=$(_local_curl POST "${CLUSTER_SETUP_PATH}" "$payload" 2>&1 || true)
    # Prüfe Membership erneut (wartet auf couchdb@<ip>)
    if membership_contains "$peer_node_name"; then
      log "Peer ${peer_node_name} erfolgreich hinzugefügt (oder bereits vorhanden)."
      return 0
    fi
    # Bei bestimmten transienten Fehlermeldungen einfach retryen
    if printf '%s' "$resp" | grep -q -E 'Invalid Host|Invalid.*port|invalid_ejson|Request to create N='; then
      # compute small jitter (0..2s) using deterministic mix of time/pid/attempt
      jitter=$(( ( $(date +%s) + $$ + attempt ) % 3 ))
      sleep_total=$((sleep_sec + jitter))
      log "Transienter Fehler beim add_node attempt ${attempt} für ${peer_ip}: ${resp}. Retry in ${sleep_sec}s + jitter ${jitter}s = ${sleep_total}s."
      sleep "$sleep_total"
      sleep_sec=$((sleep_sec * 2))
      continue
    fi
    jitter=$(( ( $(date +%s) + $$ + attempt ) % 3 ))
    sleep_total=$((sleep_sec + jitter))
    log "Add_node attempt ${attempt} für ${peer_ip} fehlgeschlagen, retry in ${sleep_sec}s + jitter ${jitter}s = ${sleep_total}s. Response: ${resp}"
    sleep "$sleep_total"
    sleep_sec=$((sleep_sec * 2))
  done
 
  log "ERROR: Konnte Peer ${peer_ip} nach ${max_attempts} Versuchen nicht hinzufügen."
  return 1
}
 
# Ensure DB exists, detect 'Request to create N=' and return 2 to signal defer
# New behaviour: defer creation if cluster membership (all_nodes) is smaller than DESIRED_CLUSTER_SIZE.
ensure_system_db() {
  db="$1"
  resp=$(_local_curl GET "/${db}" 2>/dev/null || true)
  if printf '%s' "$resp" | grep -q '"error"'; then
    # check cluster membership size before attempting creation
    memb="$(get_membership || true)"
    all_nodes=$(printf '%s' "$memb" | grep -o '"all_nodes":[^]]*]' | sed 's/^.*\[//;s/\].*$//' | tr -d '" ' || true)
    count_all=0
    IFS=','; for n in $all_nodes; do [ -n "$n" ] && count_all=$((count_all+1)); done
    IFS=' '
    if [ "${count_all:-0}" -lt "$DESIRED_CLUSTER_SIZE" ]; then
      log "Cluster size ${count_all:-0} < desired ${DESIRED_CLUSTER_SIZE}, deferring creation of ${db}"
      return 2
    fi

    log "Versuche System DB ${db} zu erstellen (pre-join)"
    resp=$(_local_curl PUT "/${db}" 2>&1 || true)
    if printf '%s' "$resp" | grep -q 'Request to create N='; then
      log "Erstelle ${db} deferred: Cluster noch nicht vollständig. Response: ${resp}"
      return 2
    fi
    if printf '%s' "$resp" | grep -q '"error"'; then
      log "Warnung: Erstellen von ${db} lieferte Fehler: ${resp}"
      return 1
    fi
    log "System DB ${db} erstellt (pre-join)."
    return 0
  else
    log "System DB ${db} bereits vorhanden"
    return 0
  fi
}
 
# Ensure application DB exists (idempotent)
ensure_app_db() {
  db="$1"
  resp=$(_local_curl GET "/${db}" 2>/dev/null || true)
  if printf '%s' "$resp" | grep -q '"error"'; then
    log "Erstelle Applikations-DB ${db}"
    _local_curl PUT "/${db}" >/dev/null 2>&1 || true
  else
    log "Applikations-DB ${db} bereits vorhanden"
  fi
}
 
main() {
  if ! wait_for_local_up; then
    log "Abbruch: lokaler CouchDB nicht erreichbar."
    exit 1
  fi
 
  # Entferne verwaiste cluster_nodes bevor wir joinen (sicherer Start)
  remove_ghost_nodes || true
 
  # Versuche System-DBs vor dem Join; akzeptiere defer (2)
  deferred=0
  ensure_system_db "_users" || rc=$?; if [ "${rc:-0}" -eq 2 ]; then deferred=1; fi
  ensure_system_db "_replicator" || rc=$?; if [ "${rc:-0}" -eq 2 ]; then deferred=1; fi
 
  # Single-node fast path: ordinal 0 ohne erkennbare peers
  case "$HOSTNAME" in
    couchdb-0)
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
        log "Single-node Start (Ordinal 0, keine weiteren Peers). Setze Readiness-Gate."
        mkdir -p /tmp /var/log || true
        touch /tmp/couchdb-ready || true
        return 0
      fi
      ;;
  esac
 
  # Scan Peers und versuche Join; warte auf peer /_up und versuche add_node
  joined_any=0
  for idx in $(seq 0 $((MAX_PEERS - 1))); do
    peer=$(peer_hostname "$idx")
    peer_short=$(printf '%s' "$peer" | cut -d. -f1)
    if [ "$peer_short" = "$HOSTNAME" ]; then
      continue
    fi
    # Versuche Peer-IP zu ermitteln (DNS oder K8s API)
    if getent hosts "$peer" >/dev/null 2>&1; then
      if attempt_add_node "$peer"; then
        joined_any=1
      fi
    else
      # DNS nicht auflösbar -> versuche K8s API
      pod_ip="$(get_pod_ip_via_k8s_api "$peer_short" || true)"
      if [ -n "$pod_ip" ]; then
        if attempt_add_node "$pod_ip"; then
          joined_any=1
        fi
      fi
    fi
  done
 
  if [ "$joined_any" -eq 1 ]; then
    log "Cluster-Join Versuche abgeschlossen."
  else
    log "Keine Peers gefunden oder alle Join-Versuche gescheitert."
  fi
 
  # After join, remove ghosts again to clean stale metadata
  remove_ghost_nodes || true
 
  # Wenn System-DB Erstellung zuvor deferred wurde, versuchen wir nach dem Join nochmal rekursiv
  if [ "$deferred" -eq 1 ]; then
    log "Versuche deferred System-DBs nach dem Join erneut zu erstellen..."
    max_wait=120
    waited=0
    while [ "$waited" -lt "$max_wait" ]; do
      all_ok=1
      ensure_system_db "_users"
      if [ $? -ne 0 ]; then all_ok=0; fi
      ensure_system_db "_replicator"
      if [ $? -ne 0 ]; then all_ok=0; fi
      if [ "$all_ok" -eq 1 ]; then
        log "Deferred System-DBs sind jetzt vorhanden."
        break
      fi
      sleep 2
      waited=$((waited + 2))
    done
    if [ "$waited" -ge "$max_wait" ]; then
      log "WARN: Deferred System-DBs konnten nach ${max_wait}s nicht erstellt werden."
    fi
  fi
 
  # Ensure application DB exists on cluster
  ensure_app_db "shisha"
 
  # Set readiness only after we ensured system+app DBs or after timeout
  mkdir -p /tmp /var/log || true
  log "Setze Readiness-Gate /tmp/couchdb-ready"
  touch /tmp/couchdb-ready || true
 
  return 0
}
 
main "$@"