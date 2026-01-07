#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------
log() {
    echo "[entrypoint] $*"
}

LAST_RESET_TS=0
RESET_BACKOFF=0

normalize_usb_id() {
    local value="$1"
    value="${value#0x}"
    printf '%s' "${value,,}"
}

# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------
get_gammu_debuglevel() {
    if [[ -n "${GAMMU_DEBUGLEVEL:-}" ]]; then
        printf '%s' "$GAMMU_DEBUGLEVEL"
        return 0
    fi
    if [[ -n "${LOGLEVEL:-}" && "${LOGLEVEL}" =~ ^[0-9]+$ ]]; then
        printf '%s' "$LOGLEVEL"
        return 0
    fi
    return 1
}

generate_config() {
    local dev="$1"
    local debuglevel=""
    debuglevel=$(get_gammu_debuglevel 2>/dev/null || true)
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
DeleteAfterReceive = yes
MultipartTimeout   = 600
CheckSecurity = 0
EOF
    if [[ -n "$debuglevel" ]]; then
        echo "DebugLevel = $debuglevel" >> /tmp/gammu-smsdrc
    fi
    ln -sf /tmp/gammu-smsdrc /tmp/gammurc
    export GAMMU_CONFIG=/tmp/gammu-smsdrc
}

# ---------------------------------------------------------------------------
# USB reset helpers
# ---------------------------------------------------------------------------
get_vid_pid_from_env() {
    if [[ -n "${USB_VID:-}" && -n "${USB_PID:-}" ]]; then
        printf '%s %s\n' "$(normalize_usb_id "$USB_VID")" "$(normalize_usb_id "$USB_PID")"
        return 0
    fi
    return 1
}

get_vid_pid_from_sysfs() {
    local modem_port="$1"
    local resolved
    local tty
    local sys_dev

    resolved=$(readlink -f "$modem_port" 2>/dev/null || true)
    if [[ -z "$resolved" ]]; then
        resolved="$modem_port"
    fi
    tty=$(basename "$resolved")

    if [[ ! -e "/sys/class/tty/$tty/device" ]]; then
        return 1
    fi

    sys_dev=$(readlink -f "/sys/class/tty/$tty/device" 2>/dev/null || true)
    if [[ -z "$sys_dev" ]]; then
        return 1
    fi

    local candidate
    local path
    for candidate in "$sys_dev" "$sys_dev/.." "$sys_dev/../.." "$sys_dev/../../.." "$sys_dev/../../../.."; do
        path=$(readlink -f "$candidate" 2>/dev/null || true)
        if [[ -f "$path/idVendor" && -f "$path/idProduct" ]]; then
            local vid
            local pid
            vid=$(cat "$path/idVendor")
            pid=$(cat "$path/idProduct")
            printf '%s %s\n' "$(normalize_usb_id "$vid")" "$(normalize_usb_id "$pid")"
            return 0
        fi
    done

    return 1
}

get_vid_pid_from_lsusb() {
    if ! command -v lsusb >/dev/null 2>&1; then
        return 1
    fi

    local usb_info
    local usb_id
    local vid
    local pid

    usb_info=$(lsusb | grep -iE 'Huawei|Modem|GSM|3G|4G|5G|LTE|HSPA|Qualcomm|Sierra|ZTE|Fibocom|Telit|Quectel|u-blox' | head -n1 || true)
    if [[ -z "$usb_info" ]]; then
        return 1
    fi

    usb_id=$(printf '%s\n' "$usb_info" | awk '{print $6}')
    vid=${usb_id%%:*}
    pid=${usb_id##*:}
    printf '%s %s\n' "$(normalize_usb_id "$vid")" "$(normalize_usb_id "$pid")"
}

resolve_usb_vid_pid() {
    if get_vid_pid_from_env; then
        return 0
    fi

    if [[ -n "${MODEM_PORT:-}" ]]; then
        if get_vid_pid_from_sysfs "$MODEM_PORT"; then
            return 0
        fi
    fi

    get_vid_pid_from_lsusb
}

find_usb_sysfs_device() {
    local vid="$1"
    local pid="$2"
    local dev
    local dev_vid
    local dev_pid

    for dev in /sys/bus/usb/devices/*; do
        if [[ ! -f "$dev/idVendor" || ! -f "$dev/idProduct" ]]; then
            continue
        fi
        dev_vid=$(cat "$dev/idVendor")
        dev_pid=$(cat "$dev/idProduct")
        if [[ "$(normalize_usb_id "$dev_vid")" == "$(normalize_usb_id "$vid")" && "$(normalize_usb_id "$dev_pid")" == "$(normalize_usb_id "$pid")" ]]; then
            basename "$dev"
            return 0
        fi
    done

    return 1
}

reset_usb_modem() {
    local min_interval="${RESET_MIN_INTERVAL:-60}"
    local backoff_step="${RESET_BACKOFF_STEP:-30}"
    local backoff_max="${RESET_BACKOFF_MAX:-300}"
    local backoff_window="${RESET_BACKOFF_WINDOW:-300}"
    local settle_seconds="${RESET_SETTLE_SECONDS:-20}"

    local now=$SECONDS
    local since=0

    if (( LAST_RESET_TS > 0 )); then
        since=$((now - LAST_RESET_TS))
        if (( since < backoff_window )); then
            RESET_BACKOFF=$((RESET_BACKOFF + backoff_step))
            if (( RESET_BACKOFF > backoff_max )); then
                RESET_BACKOFF=$backoff_max
            fi
        else
            RESET_BACKOFF=0
        fi

        local min_wait=$((min_interval + RESET_BACKOFF))
        if (( since < min_wait )); then
            local wait_seconds=$((min_wait - since))
            log "[watchdog] Backoff active; waiting ${wait_seconds}s before reset"
            sleep "$wait_seconds"
        fi
    fi

    local vid
    local pid
    if ! read -r vid pid < <(resolve_usb_vid_pid); then
        log "[watchdog] Failed to detect USB VID/PID; skipping reset"
        return 1
    fi

    log "[watchdog] Resetting USB modem ${vid}:${pid}"

    if command -v usb_modeswitch >/dev/null 2>&1; then
        usb_modeswitch -R -v "$vid" -p "$pid" >/dev/null 2>&1 || true
    else
        log "[watchdog] usb_modeswitch not found; skipping USB mode switch"
    fi

    local usb_device
    if usb_device=$(find_usb_sysfs_device "$vid" "$pid"); then
        if [[ -w /sys/bus/usb/drivers/usb/unbind && -w /sys/bus/usb/drivers/usb/bind ]]; then
            log "[watchdog] Rebinding USB device $usb_device"
            echo "$usb_device" > /sys/bus/usb/drivers/usb/unbind || true
            sleep 2
            echo "$usb_device" > /sys/bus/usb/drivers/usb/bind || true
        else
            log "[watchdog] USB sysfs bind/unbind not available"
        fi
    else
        log "[watchdog] No matching USB device found for ${vid}:${pid}"
    fi

    LAST_RESET_TS=$SECONDS
    if (( settle_seconds > 0 )); then
        log "[watchdog] Waiting ${settle_seconds}s after USB reset"
        sleep "$settle_seconds"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Modem detection helpers
# ---------------------------------------------------------------------------
detect_modem() {
    local candidates=()
    local timeout_seconds="${MODEM_DETECT_TIMEOUT:-10}"
    local nullglob_state

    if [[ -n "${MODEM_PORT:-}" ]]; then
        candidates+=("${MODEM_PORT}")
    fi

    nullglob_state=$(shopt -p nullglob)
    shopt -s nullglob
    local p
    for p in /dev/serial/by-id/* /dev/serial/by-path/* /dev/ttyUSB*; do
        candidates+=("${p}")
    done
    eval "$nullglob_state"

    local -A seen=()
    for p in "${candidates[@]}"; do
        [[ -e "$p" ]] || continue
        if [[ -n "${seen[$p]:-}" ]]; then
            continue
        fi
        seen[$p]=1
        log "[detect_modem] probing $p"
        if timeout "$timeout_seconds" gammu -c <(printf '[gammu]\ndevice=%s\nconnection=at\n' "$p") identify \
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

# ---------------------------------------------------------------------------
# Watchdog helpers
# ---------------------------------------------------------------------------
start_gammu_smsd() {
    if command -v stdbuf >/dev/null 2>&1; then
        exec stdbuf -oL -eL gammu-smsd -c /tmp/gammu-smsdrc
    else
        exec gammu-smsd -c /tmp/gammu-smsdrc
    fi
}

run_smsd_with_watchdog() {
    local threshold="${MODEM_TIMEOUT_THRESHOLD:-3}"
    local timeout_count=0
    local line
    local nocasematch_state

    nocasematch_state=$(shopt -p nocasematch)
    shopt -s nocasematch

    coproc SMSD_PROC { start_gammu_smsd 2>&1; }
    local smsd_pid=$!

    if [[ -z "${smsd_pid:-}" ]]; then
        log "[watchdog] Failed to start gammu-smsd"
        eval "$nocasematch_state"
        return 1
    fi

    while IFS= read -r line <&"${SMSD_PROC[0]}"; do
        printf '%s\n' "$line"
        if [[ "$line" =~ (TIMEOUT|No response in specified timeout|Probably the phone is not connected|Already hit 250 errors) ]]; then
            timeout_count=$((timeout_count + 1))
            log "[watchdog] Modem timeout pattern ${timeout_count}/${threshold}"
            if (( timeout_count >= threshold )); then
                log "[watchdog] Threshold reached; stopping gammu-smsd"
                kill "$smsd_pid" 2>/dev/null || true
                wait "$smsd_pid" 2>/dev/null || true
                eval "$nocasematch_state"
                return 2
            fi
        else
            timeout_count=0
        fi
    done

    local smsd_rc=0
    if ! wait "$smsd_pid"; then
        smsd_rc=$?
    fi

    eval "$nocasematch_state"
    return "$smsd_rc"
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

    while true; do
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

        log "Starting sms-daemon"
        local smsd_rc=0
        if run_smsd_with_watchdog; then
            smsd_rc=0
        else
            smsd_rc=$?
        fi

        if (( smsd_rc == 2 )); then
            log "[watchdog] Modem timeout threshold reached; resetting USB"
            reset_usb_modem || true
        else
            log "[watchdog] gammu-smsd exited (rc=${smsd_rc}); restarting detection"
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
