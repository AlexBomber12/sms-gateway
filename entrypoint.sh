#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[entrypoint] $*"; }

MODEM_DEVICE="${MODEM_DEVICE:-}"
LOGLEVEL="${LOGLEVEL:-1}"
GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
GAMMU_CONFIG_PATH="${GAMMU_CONFIG_PATH:-/tmp/gammu-smsdrc}"

mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

device_ok(){
    local dev="$1"
    if timeout 3 gammu --device "$dev" --connection at115200 --at "AT" 2>&1 | grep -q "OK"; then
        return 0
    fi
    return 1
}

find_modem(){
    if [ -n "$MODEM_DEVICE" ] && device_ok "$MODEM_DEVICE"; then
        echo "$MODEM_DEVICE"
        return 0
    fi
    for dev in /dev/serial/by-id/usb-Huawei_Technologies_HUAWEI_Mobile-*; do
        [ -e "$dev" ] || continue
        if device_ok "$dev"; then
            echo "$dev"
            return 0
        fi
    done
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$dev" ] || continue
        if device_ok "$dev"; then
            echo "$dev"
            return 0
        fi
    done
    return 1
}

generate_config(){
    local dev="$1"
    cat > "$GAMMU_CONFIG_PATH" <<EOF_CONF
[gammu]
device = $dev
connection = at115200
logformat = textalldate

[smsd]
service = files
inboxpath = ${GAMMU_SPOOL_PATH}/inbox/
outboxpath = ${GAMMU_SPOOL_PATH}/outbox/
sentpath = ${GAMMU_SPOOL_PATH}/sent/
errorpath = ${GAMMU_SPOOL_PATH}/error/
RunOnReceive = python3 /app/on_receive.py
debuglevel = ${LOGLEVEL}
logfile = /dev/stdout
EOF_CONF
}

while true; do
    if dev=$(find_modem); then
        generate_config "$dev"
        log "✅  Using modem $dev"
        if gammu-smsd -c "$GAMMU_CONFIG_PATH"; then
            log "gammu-smsd exited normally"
        else
            log "gammu-smsd crashed, restarting" 
        fi
    else
        log "Waiting for modem ..."
        sleep 5
        continue
    fi
    sleep 5
done
