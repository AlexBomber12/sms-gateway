#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------
log() {
    echo "[entrypoint] $*"
}

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
    local candidates=()
    if [[ -n "${MODEM_PORT:-}" ]]; then
        candidates+=("${MODEM_PORT}")
    fi
    for p in /dev/ttyUSB* /dev/serial/by-id/*; do
        candidates+=("${p}")
    done
    for p in "${candidates[@]}"; do
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

# ---------------------------------------------------------------------------
# Watchdog loop
# ---------------------------------------------------------------------------
watchdog_loop() {
    local smsd_pid="$1"
    shift
    while kill -0 "$smsd_pid" >/dev/null 2>&1; do
        if timeout 5 bash -c 'echo -e "AT\r" | socat - /dev/ttyUSB0,crnl | grep -q "OK"'; then
            sleep 30
            continue
        fi
        log "[watchdog] Modem not responding to AT command, performing USB reset"

        USB_INFO=$(lsusb | grep -iE 'Huawei|modem|E352' | head -n1 || true)

        if [[ -z "${USB_INFO:-}" ]]; then
            log "[watchdog] lsusb did not detect any modem device, aborting reset"
            return 1
        fi

        USB_VID=$(echo "$USB_INFO" | awk '{print $6}' | cut -d':' -f1)
        USB_PID=$(echo "$USB_INFO" | awk '{print $6}' | cut -d':' -f2)

        if [[ -z "${USB_VID:-}" || -z "${USB_PID:-}" ]]; then
            log "[watchdog] Failed to detect USB VID/PID, aborting reset"
            return 1
        fi

        usb_modeswitch -R -v "$USB_VID" -p "$USB_PID" >/dev/null 2>&1 || true

        log "Waiting 20 seconds after USB reset"
        sleep 20
        pkill -9 -x gammu-smsd 2>/dev/null || true
        # shellcheck disable=SC2093
        exec "$0" "$@"
    done

}

main() {
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
