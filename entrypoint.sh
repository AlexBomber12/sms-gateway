#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[entrypoint] $*"
}

: "${PROBE_TIMEOUT:=90}"   # seconds before giving up
: "${SCAN_SLEEP:=1}"       # pause between scan rounds

generate_config() {
  local dev="$1"
  cat > /tmp/gammu-smsdrc <<EOF_CONF
[gammu]
device = ${dev}
connection = at

[smsd]
service      = files
inboxpath    = ${GAMMU_SPOOL_PATH}/inbox/
outboxpath   = ${GAMMU_SPOOL_PATH}/outbox/
sentpath     = ${GAMMU_SPOOL_PATH}/sent/
errorpath    = ${GAMMU_SPOOL_PATH}/error/
RunOnReceive = python3 /app/on_receive.py
logfile      = /dev/stdout
EOF_CONF
  ln -sf /tmp/gammu-smsdrc /tmp/gammurc
}

use_mounted_config() {
  if [[ -f /etc/gammu-smsdrc ]]; then
    log "Using smsdrc from volume"
    cp /etc/gammu-smsdrc /tmp/gammu-smsdrc
    ln -sf /tmp/gammu-smsdrc /tmp/gammurc
    return 0
  fi
  return 1
}

make_temp_rc() {
    local port="$1" rc
    rc="$(mktemp /tmp/gammu-rc.XXXXXX)"
    cat >"$rc"<<EOF
[gammu]
device = ${port}
connection = at
EOF
    echo "$rc"
}

auto_detect_port() {
    local dev
    dev=$(gammu-detect 2>/dev/null | awk -F'=' '/^device/{gsub(/^[ \t]+/,"",$2);print $2;exit}')
    [[ -n "$dev" && -e "$dev" ]] || return 1
    log "🛰  gammu-detect suggested ${dev}"
    MODEM_PORT="$dev"
    export MODEM_PORT
    return 0
}

probe_modem() {
    local port="$1" rc
    rc=$(make_temp_rc "$port")
    timeout 20 gammu -c "$rc" identify >/dev/null 2>&1
    local status=$?
    rm -f "$rc"
    return $status
}

detect_modem() {
    # 0) honour explicit env
    if [[ -n "${MODEM_PORT:-}" && -e "${MODEM_PORT}" ]]; then
        log "✅ Using pre-set ${MODEM_PORT}"
        generate_config "${MODEM_PORT}"
        return 0
    fi

    # 1) one-off auto scan
    auto_detect_port && { generate_config "${MODEM_PORT}"; return 0; }

    # 2) manual round-robin
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
    log "⛔  No responsive modem after ${PROBE_TIMEOUT}s"
    return 70
}

main() {
  GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
  mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

  if ! use_mounted_config; then
    detect_modem || exit 70
  fi

  export GAMMU_CONFIG=/tmp/gammu-smsdrc
  args=( -c /tmp/gammu-smsdrc )

  if [[ -n "${LOGLEVEL:-}" ]]; then
    grep -q '^\[smsd\]' /tmp/gammu-smsdrc || echo '[smsd]' >> /tmp/gammu-smsdrc
    sed -i '/^\[smsd\]/,/^\[/ { /^DebugLevel[[:space:]]*=.*/d }' /tmp/gammu-smsdrc
    sed -i '/^\[smsd\]/a DebugLevel = '"$LOGLEVEL"'' /tmp/gammu-smsdrc
  fi

  [[ "${FOREGROUND:-false}" != "true" ]] && args+=( --daemon )
  exec gammu-smsd "${args[@]}"
}

# ---- Immediate bypasses -------------------------------------------------
# Skip the modem scan entirely during CI or when explicitly requested.
if [[ "${CI_MODE:-}" == "true" || "${SKIP_MODEM:-}" == "true" ]]; then
  log "Modem scan disabled."
  [[ $# -gt 0 ]] && exec "$@"
  exit 0
fi

main "$@"
