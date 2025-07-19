#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[entrypoint] $*"
}

generate_config() {
  local dev="$1"
  cat > /tmp/gammu-smsdrc <<EOF
[gammu]
device = ${dev}
connection = at

[smsd]
service = files
EOF
  ln -sf /tmp/gammu-smsdrc /tmp/gammurc
}

probe_modem() {
  timeout 12 gammu --identify -c /tmp/gammu-smsdrc >/dev/null 2>&1
}

detect_modem() {
  local start=$SECONDS
  local deadline=$((start + 30))
  local candidates=( )
  [[ -n "${MODEM_PORT:-}" ]] && candidates+=("${MODEM_PORT}")
  candidates+=(/dev/serial/by-id/* /dev/ttyUSB*)

  while (( SECONDS < deadline )); do
    for dev in "${candidates[@]}"; do
      [[ -e "$dev" ]] || continue
      generate_config "$dev"
      if probe_modem; then
        DEV="$dev"
        export DEV
        log "✅ Using ${DEV}"
        return 0
      fi
    done
    sleep 1
  done
  log "Modem not found"
  return 70
}

main() {
  LOGLEVEL="${LOGLEVEL:-1}"
  GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
  mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

  detect_modem || exit 70

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
