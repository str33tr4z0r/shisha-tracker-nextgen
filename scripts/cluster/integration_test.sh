#!/bin/sh
set -eu
NS=shisha
CYCLE_COUNT=${CYCLE_COUNT:-3}
SLEEP_SHORT=5
SLEEP_MED=15
SLEEP_LONG=30
LOG="[integration-test]"

# detect microk8s
USE_MICROK8S=0
if command -v microk8s >/dev/null 2>&1 && microk8s kubectl --help >/dev/null 2>&1; then
  USE_MICROK8S=1
fi
kc() {
  if [ "$USE_MICROK8S" -eq 1 ]; then
    microk8s kubectl -n "$NS" "$@"
  else
    kubectl -n "$NS" "$@"
  fi
}

log() {
  printf '%s %s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$LOG" "$*"
}

wait_for_pods_ready() {
  # Wait for desired pods where the sidecar has signaled readiness
  desired="$1"
  timeout=${2:-180}
  start=$(date +%s)
  while true; do
    # count pods that have the readiness file set by sidecar (/tmp/couchdb-ready)
    ready=0
    for p in $(kc get pods -l app=couchdb -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
      if kc exec "$p" -c cluster-manager -- sh -c 'test -f /tmp/couchdb-ready' >/dev/null 2>&1; then
        ready=$((ready + 1))
      fi
    done
    if [ "$ready" = "$desired" ]; then
      log "Pods ready (sidecar-file): $ready"
      return 0
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      log "Timeout waiting for $desired pods to be ready (got $ready)"
      return 1
    fi
    sleep 3
  done
}
 
collect_logs() {
  outdir="${1:-./integration-logs}"
  mkdir -p "$outdir"
  for p in $(kc get pods -l app=couchdb -o jsonpath='{.items[*].metadata.name}' || true); do
    log "Collect logs for $p"
    kc exec "$p" -c cluster-manager -- sh -c 'test -f /tmp/cluster-manager-poststart.log && cat /tmp/cluster-manager-poststart.log || echo "no-poststart"' > "$outdir/${p}-poststart.log" || true
    kc exec "$p" -c couchdb -- sh -c 'curl -sS http://127.0.0.1:5984/_membership || true' > "$outdir/${p}-membership.json" || true
    kc exec "$p" -c couchdb -- sh -c 'test -f /tmp/couchdb-ready && echo ready || echo not-ready' > "$outdir/${p}-ready" || true
  done
}
 
# Wait for the statefulset to exist before attempting scale operations.
wait_for_statefulset_exists() {
  timeout=${1:-120}
  start=$(date +%s)
  while true; do
    if kubectl -n "$NS" get statefulset couchdb >/dev/null 2>&1; then
      log "StatefulSet couchdb exists"
      return 0
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      log "Timeout waiting for statefulset couchdb to exist"
      return 1
    fi
    sleep 2
  done
}
 
# Scale with guard: wait for statefulset existence then scale.
scale_statefulset() {
  replicas="$1"
  log "Scaling statefulset to $replicas (guarded)"
  if ! wait_for_statefulset_exists 120; then
    log "Cannot scale: statefulset couchdb does not exist"
    return 1
  fi
  kc scale statefulset couchdb --replicas="$replicas" || true
}
 
wait_for_deletion() {
  kind="$1"
  name="$2"
  timeout=${3:-120}
  start=$(date +%s)
  while kc get "$kind" "$name" >/dev/null 2>&1; do
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      log "Timeout waiting for deletion of $kind/$name"
      return 1
    fi
    sleep 2
  done
  log "$kind/$name deleted"
  return 0
}

main() {
  log "Starting integration cycles: CYCLE_COUNT=${CYCLE_COUNT}"
  i=1
  while [ $i -le "$CYCLE_COUNT" ]; do
    log "Cycle $i: apply manifests"
    kubectl apply -f k8s/database/couchdb-scripts-configmap.yaml || true
    kubectl apply --validate=false -f k8s/database/couchdb-statefulset.yaml || true
    sleep $SLEEP_SHORT
    log "Wait for initial single pod (replicas may be 1)"
    wait_for_pods_ready 1 180 || log "warn: initial pod not ready"

    log "Scale up to 3 replicas"
    scale_statefulset 3
    wait_for_pods_ready 3 300 || log "warn: scaled pods not all ready"
    collect_logs "./integration-logs/cycle-${i}"

    log "Scale down to 1 replica"
    scale_statefulset 1
    wait_for_pods_ready 1 180 || log "warn: scale down pod not ready"
    collect_logs "./integration-logs/cycle-${i}-post-scale-down"

    log "Run aggressive clean to simulate destructive reset"
    ./scripts/aggressive_clean.sh --force || log "aggressive clean returned non-zero"

    # Wait for resources to be deleted
    sleep $SLEEP_LONG

    # Ensure the statefulset is gone before next apply
    wait_for_deletion statefulset couchdb 120 || true

    log "Cycle $i completed"
    i=$((i + 1))
    sleep 5
  done
  log "Integration cycles finished"
}

main "$@"