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
EOF
    ln -sf /tmp/gammu-smsdrc /tmp/gammurc
    export GAMMU_CONFIG=/tmp/gammu-smsdrc
}

# Capture USB identifiers for the modem from sysfs if available.  These
# values are later refined through lsusb when performing USB resets.
capture_usb_ids() {
    local dev="$1" base
    base="/sys/class/tty/${dev##*/}/device"
    if [[ -r "$base/../idVendor" ]]; then
        USB_VID=$(cat "$base/../idVendor" 2>/dev/null || true)
        USB_PID=$(cat "$base/../idProduct" 2>/dev/null || true)
        USB_BUS=$(cat "$base/../busnum" 2>/dev/null || true)
        USB_DEVNUM=$(cat "$base/../devnum" 2>/dev/null || true)
        export USB_VID USB_PID USB_BUS USB_DEVNUM
        log "Captured USB IDs ${USB_VID:-?}:${USB_PID:-?}"
    fi
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
            capture_usb_ids "$p"
            return 0
        fi
    done
    return 1
}

# Parse lsusb output to refresh USB_VID and USB_PID.  If the modem was
# previously identified we try to match by bus/device numbers; otherwise the
# first lsusb line is used as best effort.
determine_usb_ids() {
    if ! command -v lsusb >/dev/null 2>&1; then
        log "lsusb not found; cannot determine USB IDs"
        return 1
    fi
    local line
    if [[ -n "${USB_BUS:-}" && -n "${USB_DEVNUM:-}" ]]; then
        line=$(lsusb | awk -v b="$USB_BUS" -v d="$(printf '%03d' "$USB_DEVNUM"):" '$2==b && $4==d {print; exit}')
    fi
    [[ -n "$line" ]] || line=$(lsusb | head -n1)
    USB_VID=$(echo "$line" | awk '{print $6}' | cut -d: -f1)
    USB_PID=$(echo "$line" | awk '{print $6}' | cut -d: -f2)
    export USB_VID USB_PID
    log "lsusb detected VID:PID ${USB_VID}:${USB_PID}"
    return 0
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
        determine_usb_ids || true
        usb_modeswitch -R -v "$USB_VID" -p "$USB_PID" >/dev/null 2>&1 || true
        log "Waiting 20 seconds after USB reset"
        sleep 20
        pkill -9 -x gammu-smsd 2>/dev/null || true
        # shellcheck disable=SC2093
        exec "$0" "$@"
    done
}

main() {
    GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
    mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

    service cron start >/dev/null 2>&1 || true

    log "Starting modem detection"
    local start=$SECONDS
    until detect_modem; do
        if (( SECONDS - start > 60 )); then
            log "Initial detection timeout; attempting USB reset"
            determine_usb_ids || true
            usb_modeswitch -R -v "$USB_VID" -p "$USB_PID" >/dev/null 2>&1 || true
            log "Waiting 20 seconds after USB reset"
            sleep 20
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
    watchdog_loop "$smsd_pid" "$@"
}

main "$@"

