#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[entrypoint] $*"
}

detect_device() {
  for dev in /dev/serial/by-id/*; do
    [[ -r "$dev" ]] && { echo "$dev"; return; }
  done
  echo "/dev/ttyUSB0"
}

generate_configs() {
  local dev="$1"
  cat > /tmp/gammurc <<EOF
[gammu]
device  = ${dev}
connection = at
EOF

  cat > /tmp/gammu-smsdrc <<EOF
[gammu]
device  = ${dev}
connection = at

[smsd]
service = files
EOF
}

wait_for_modem() {
  local timeout="${MODEM_TIMEOUT:-30}"
  until gammu identify -c /tmp/gammurc >/dev/null 2>&1; do
    ((timeout--)) || { log "Modem not found"; return 70; }
    sleep 1
  done
  log "Modem detected"
}

main() {
  LOGLEVEL="${LOGLEVEL:-1}"
  GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
  mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

  DEV="$(detect_device)"
  export DEV
  generate_configs "$DEV"

  wait_for_modem || exit 70

  exec gammu-smsd -c /tmp/gammu-smsdrc -f
}

# ---- Immediate bypasses -------------------------------------------------
# Skip the modem scan entirely during CI or when explicitly requested.
if [[ "${CI_MODE:-}" == "true" || "${SKIP_MODEM:-}" == "true" ]]; then
  log "Modem scan disabled."
  [[ $# -gt 0 ]] && exec "$@"
  exit 0
fi

main "$@"
