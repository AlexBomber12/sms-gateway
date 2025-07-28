#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[entrypoint] $*"
}

: "${PROBE_TIMEOUT:=90}"   # seconds before giving up
: "${SCAN_SLEEP:=1}"       # pause between scan rounds

# Skip modem scan when running tests under pytest.
if [[ "${1:-}" == "pytest" ]] ||
   { [[ "${1:-}" =~ ^python(3)?$ ]] && [[ "${2:-}" == "-m" ]] && [[ "${3:-}" == "pytest" ]]; }; then
  log "Running pytest; skipping modem scan."
  exec "$@"
fi

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
  for p in /dev/ttyUSB* /dev/serial/by-id/*; do
    [ -e "$p" ] || continue
    if timeout 8 gammu identify -d 0 -c <(printf '[gammu]\ndevice=%s\nconnection=at\n' "$p") >/dev/null 2>&1; then
      echo "[detect_modem] found working port $p"
      generate_config "$p"
      return 0
    fi
  done
  return 1
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

  service cron start >/dev/null

  echo "[entrypoint] 🕒 waiting 15s for modem enumeration…"
  sleep 15

  if ! use_mounted_config; then
    tries=0
    max_tries=3
    until detect_modem; do
      ((tries++))
      if [ $tries -lt $max_tries ]; then
        echo "[retry] $tries/$max_tries"
        sleep 5
        continue
      fi
      echo "[entrypoint] ❌ modem not found – exit 70"
      exit 70
    done
  fi

  export GAMMU_CONFIG=/tmp/gammu-smsdrc

  if [[ -n "${LOGLEVEL:-}" ]]; then
    grep -q '^\[smsd\]' /tmp/gammu-smsdrc || echo '[smsd]' >> /tmp/gammu-smsdrc
    sed -i '/^\[smsd\]/,/^\[/ { /^DebugLevel[[:space:]]*=.*/d }' /tmp/gammu-smsdrc
    sed -i '/^\[smsd\]/a DebugLevel = '"$LOGLEVEL"'' /tmp/gammu-smsdrc
  fi

  fail=0
  pkill -9 -x gammu-smsd 2>/dev/null || true
  while true; do
    echo "[watchdog] starting sms-daemon"
    gammu-smsd -c /tmp/gammu-smsdrc
    rc=$?
    pkill -9 -x gammu-smsd 2>/dev/null || true
    if [ $rc -ne 0 ]; then
      ((fail++))
      echo "[watchdog] gammu-smsd exited rc=$rc (fail=$fail)"
      if [ $fail -ge 3 ]; then
        echo "[watchdog] re-probing modem"
        if detect_modem; then
          fail=0
        else
          echo "[watchdog] modem still missing, exiting for Docker restart"
          exit 74
        fi
      fi
    else
      # keep fail count until modem re-probe succeeds
      :
    fi
    sleep 2
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
