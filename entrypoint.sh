#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[entrypoint] $*"
}

: "${PROBE_TIMEOUT:=90}"   # seconds to keep looking before giving up
: "${SCAN_SLEEP:=1}"       # delay between scan rounds

generate_config() {
  local dev="$1"
  cat > /tmp/gammu-smsdrc <<EOF_CONF
[gammu]
device = ${dev}
connection = at

[smsd]
service = files
EOF_CONF
  ln -sf /tmp/gammu-smsdrc /tmp/gammurc
}

auto_detect_port() {
    local dev
    dev=$(gammu --identify 2>/dev/null | awk -F': ' '$1=="Device"{print $2}')
    [[ -n "$dev" && -e "$dev" ]] || return 1   # fail if nothing found
    log "🛰  Gammu autodetected ${dev}"
    MODEM_PORT="$dev"
    export MODEM_PORT
    return 0
}

probe_modem() {
    local port="$1"
    timeout 20 gammu --device "$port" --connection at --identify \
        >/dev/null 2>&1
}

detect_modem() {
    # 0) Honour explicit env
    if [[ -n "${MODEM_PORT:-}" && -e "${MODEM_PORT}" ]]; then
        log "✅ Using pre-set ${MODEM_PORT}"
        generate_config "${MODEM_PORT}"
        return 0
    fi

    # 1) One-off Gammu auto-scan
    auto_detect_port && { generate_config "${MODEM_PORT}"; return 0; }

    # 2) Manual round-robin until deadline
    local deadline=$((SECONDS + PROBE_TIMEOUT))
    local ports
    while (( SECONDS < deadline )); do
        ports=( /dev/serial/by-id/* /dev/ttyUSB* /dev/ttyACM* )
        for p in "${ports[@]}"; do
            [[ -e "$p" ]] || continue
            probe_modem "$p" && {
                log "✅ Using $p"
                generate_config "$p"
                return 0
            }
        done
        sleep "${SCAN_SLEEP}"
    done
    log "⛔  No responsive modem found after ${PROBE_TIMEOUT}s"
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
