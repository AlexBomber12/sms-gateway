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
  export GAMMU_CONFIG=/tmp/gammu-smsdrc
}

use_mounted_config() {
  if [[ -n "${MODEM_PORT:-}" ]]; then
    # Skip mounted config when a modem port is pre-defined
    return 1
  fi
  if [[ -f /etc/gammu-smsdrc ]]; then
    log "Using smsdrc from volume"
    cp /etc/gammu-smsdrc /tmp/gammu-smsdrc
    ln -sf /tmp/gammu-smsdrc /tmp/gammurc
    export GAMMU_CONFIG=/tmp/gammu-smsdrc
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
    # Honour explicit env if it points to an existing device
    if [[ -n "${MODEM_PORT:-}" && -e "${MODEM_PORT}" ]]; then
        log "✅ Using pre-set ${MODEM_PORT}"
        generate_config "${MODEM_PORT}"
        return 0
    fi

    local deadline=$((SECONDS + PROBE_TIMEOUT))
    while (( SECONDS < deadline )); do
        for p in /dev/ttyUSB* /dev/serial/by-id/*; do
            [[ -e "$p" ]] || continue
            if gammu identify -d 0 -c <(printf '[gammu]\ndevice=%s\nconnection=at\n' "$p") >/dev/null 2>&1; then
                log "✅ Using $p"
                MODEM_PORT="$p"
                export MODEM_PORT
                generate_config "$p"
                return 0
            fi
        done
        sleep "${SCAN_SLEEP}"
    done

    log "⛔  No responsive modem after ${PROBE_TIMEOUT}s"
    return 70
}

reprobe_modem() {
    detect_modem && {
        local new_dev="$MODEM_PORT"
        log "[watchdog] Switched to ${new_dev}"
    }
}

main() {
  GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
  mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

  if ! use_mounted_config; then
    detect_modem || exit 70
  fi

  export GAMMU_CONFIG=/tmp/gammu-smsdrc

  if [[ -n "${LOGLEVEL:-}" ]]; then
    grep -q '^\[smsd\]' /tmp/gammu-smsdrc || echo '[smsd]' >> /tmp/gammu-smsdrc
    sed -i '/^\[smsd\]/,/^\[/ { /^DebugLevel[[:space:]]*=.*/d }' /tmp/gammu-smsdrc
    sed -i '/^\[smsd\]/a DebugLevel = '"$LOGLEVEL"'' /tmp/gammu-smsdrc
  fi

  fail=0
  while true; do
    gammu-smsd -c /tmp/gammu-smsdrc
    rc=$?
    if [ $rc -ne 0 ]; then
      ((fail++))
      if [ $fail -ge 3 ]; then
        log "[watchdog] too many failures ($fail). Re-probing modem"
        detect_modem
        fail=0
      fi
    else
      fail=0
    fi
    sleep 5
  done
}

# ---- Immediate bypasses -------------------------------------------------
# Skip the modem scan entirely during CI or when explicitly requested.
if [[ "${CI_MODE:-}" == "true" || "${SKIP_MODEM:-}" == "true" ]]; then
  log "Modem scan disabled."
  [[ $# -gt 0 ]] && exec "$@"
  exit 0
fi

main "$@"
