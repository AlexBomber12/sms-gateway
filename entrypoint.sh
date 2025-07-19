#!/usr/bin/env bash
set -euo pipefail

log() { echo "[entrypoint] $*"; }

find_device() {
  for d in /dev/serial/by-id/* /dev/ttyUSB0; do
    [[ -r "$d" ]] && echo "$d" && return 0
  done
  return 1
}

generate_configs() {
  local dev="$1"
  cat > /tmp/gammurc <<CONF
[gammu]
device  = ${dev}
connection = at
CONF
  cat > /tmp/gammu-smsdrc <<CONF
[gammu]
device  = ${dev}
connection = at

[smsd]
service = files
CONF
}

wait_for_modem() {
  local timeout="${MODEM_TIMEOUT:-30}"
  until gammu --identify -c /tmp/gammurc >/dev/null 2>&1; do
    ((timeout--)) || { log "Modem not found"; exit 70; }
    sleep 1
  done
  log "Modem detected"
}

main() {
  if [[ "${CI_MODE:-}" == "true" || "${SKIP_MODEM:-}" == "true" ]]; then
    log "Modem scan disabled."
    [[ $# -gt 0 ]] && exec "$@"
    exit 0
  fi

  LOGLEVEL="${LOGLEVEL:-1}"
  GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
  mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

  DEV=$(find_device || true)
  if [[ -z "${DEV:-}" ]]; then
    log "No modem device found"
    exit 70
  fi
  export DEV
  generate_configs "$DEV"
  wait_for_modem
  exec gammu-smsd -c /tmp/gammu-smsdrc -f
}

main "$@"
