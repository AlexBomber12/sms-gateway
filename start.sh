#!/usr/bin/env bash
set -euo pipefail

# Resolve directory of this script for relative paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

log() { echo "[start.sh] $*"; }

: "${DEVICE:?DEVICE variable is required}"
: "${BAUDRATE:?BAUDRATE variable is required}"
LOGLEVEL="${LOGLEVEL:-1}"

GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
GAMMU_CONFIG_PATH="${GAMMU_CONFIG_PATH:-/etc/gammu-smsdrc}"

log "Starting with device $DEVICE baudrate $BAUDRATE"

mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

if [ ! -f "$GAMMU_CONFIG_PATH" ]; then
    log "Generating default smsdrc"
    mkdir -p "$(dirname "$GAMMU_CONFIG_PATH")"
    cat > "$GAMMU_CONFIG_PATH" <<EOF_CONF
[gammu]
device     = ${DEVICE}
connection = at
baudrate   = ${BAUDRATE}
logformat  = textalldate

[smsd]
service      = files
inboxpath    = ${GAMMU_SPOOL_PATH}/inbox/
outboxpath   = ${GAMMU_SPOOL_PATH}/outbox/
sentpath     = ${GAMMU_SPOOL_PATH}/sent/
errorpath    = ${GAMMU_SPOOL_PATH}/error/
RunOnReceive = python3 "${SCRIPT_DIR}/on_receive.py"
debuglevel   = ${LOGLEVEL}
logfile      = /dev/stdout
EOF_CONF
else
    log "Using existing smsdrc from volume"
fi

if [ "${1:-}" = "--dry-run" ]; then
    log "Dry run requested - not starting gammu-smsd"
    exit 0
fi

exec gammu-smsd -c "$GAMMU_CONFIG_PATH"
