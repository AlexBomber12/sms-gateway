#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------
log() {
    echo "[entrypoint] $*"
}

# Skip modem work when executing tests directly
if [[ "${1:-}" == "pytest" ]] || {
        [[ "${1:-}" =~ ^python(3)?$ ]] &&
        [[ "${2:-}" == "-m" ]] &&
        [[ "${3:-}" == "pytest" ]];
    }; then
    log "Running pytest; skipping modem scan."
    exec "$@"
fi

# ---- Immediate bypasses -------------------------------------------------
if [[ "${CI_MODE:-}" == "true" || "${SKIP_MODEM:-}" == "true" ]]; then
    log "Modem scan disabled."
    if [[ $# -gt 0 ]]; then
        exec "$@"
    else
        exec tail -f /dev/null
    fi
fi

# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------
generate_config() {
    local dev="$1"
    cat > /tmp/gammu-smsdrc <<EOF
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
CheckSecurity = 0
EOF
    ln -sf /tmp/gammu-smsdrc /tmp/gammurc
    export GAMMU_CONFIG=/tmp/gammu-smsdrc
}

# ---------------------------------------------------------------------------
# Modem detection helpers
# ---------------------------------------------------------------------------
detect_modem() {
    for p in /dev/ttyUSB* /dev/serial/by-id/*; do
        [ -e "$p" ] || continue
        log "[detect_modem] probing $p"
        if timeout 10 gammu -c <(printf '[gammu]\ndevice=%s\nconnection=at\n' "$p") identify \
            >/dev/null 2>&1; then
            log "[detect_modem] found working modem on $p"
            MODEM_PORT="$p"
            export MODEM_PORT
            generate_config "$p"
            return 0
        fi
    done
    return 1
}

check_modem() {
  timeout 5 bash -c 'echo -e "AT\r" | socat - /dev/ttyUSB0,crnl | grep -q "OK"' 2>/dev/null
}

reset_usb_modem() {
  log "[watchdog] Modem not responding to AT command, performing USB reset"
  
  USB_INFO=$(lsusb | grep -iE 'Huawei|modem|E352' | head -n1)
  USB_VID=$(echo "$USB_INFO" | awk '{print $6}' | cut -d':' -f1)
  USB_PID=$(echo "$USB_INFO" | awk '{print $6}' | cut -d':' -f2)

  if [[ -z "${USB_VID:-}" || -z "${USB_PID:-}" ]]; then
    log "[watchdog] Failed to detect USB VID/PID, aborting reset"
    return 1
  fi

  usb_modeswitch -R -v "$USB_VID" -p "$USB_PID"
  log "[watchdog] Waiting 20 seconds after USB reset"
  sleep 20
}

main() {
    GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
    mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

    service cron start >/dev/null 2>&1 || true

    log "Starting modem detection"
    local start=$SECONDS
    until detect_modem; do
        if (( SECONDS - start > 60 )); then
            reset_usb_modem || true
            start=$SECONDS
        fi
        log "Modem not detected yet; retrying in 5s"
        sleep 5
    done

    if [[ -n "${LOGLEVEL:-}" ]]; then
        grep -q '^\[smsd\]' /tmp/gammu-smsdrc || echo '[smsd]' >> /tmp/gammu-smsdrc
        sed -i '/^\[smsd\]/,/^\[/ { /^DebugLevel[[:space:]]*=.*/d }' /tmp/gammu-smsdrc
        sed -i '/^\[smsd\]/a DebugLevel = '"$LOGLEVEL"'' /tmp/gammu-smsdrc
    fi

    log "Starting sms-daemon"
    gammu-smsd -c /tmp/gammu-smsdrc &
    local smsd_pid=$!

    while true; do
      if ! check_modem; then
        reset_usb_modem || continue
        log "[watchdog] Restarting modem detection logic"
        exec "$0"
      fi
      sleep 30
    done &

    wait "$smsd_pid"
}

main "$@"

