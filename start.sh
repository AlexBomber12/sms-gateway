#!/usr/bin/env bash
set -euo pipefail

log() { echo "[start.sh] $*"; }

: "${DEVICE:?DEVICE variable is required}"
: "${BAUDRATE:?BAUDRATE variable is required}"
LOGLEVEL="${LOGLEVEL:-1}"
DELIVERY_MODE="${DELIVERY_MODE:-direct}"
DELIVERY_MODE="${DELIVERY_MODE,,}"
RUN_ON_RECEIVE="python3 /app/on_receive.py"

GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"
GAMMU_CONFIG_PATH="${GAMMU_CONFIG_PATH:-/etc/gammu-smsdrc}"

log "Starting with device $DEVICE baudrate $BAUDRATE"

if [[ "$DELIVERY_MODE" == "queue" ]]; then
    RUN_ON_RECEIVE="python3 /app/on_receive.py --enqueue"
elif [[ "$DELIVERY_MODE" != "direct" ]]; then
    log "Unknown DELIVERY_MODE '$DELIVERY_MODE'; defaulting to direct"
    DELIVERY_MODE="direct"
fi

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
RunOnReceive = ${RUN_ON_RECEIVE}
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

if [[ "$DELIVERY_MODE" == "queue" ]]; then
    log "Starting queue worker"
    python3 /app/queue_worker.py &
fi

exec gammu-smsd -c "$GAMMU_CONFIG_PATH"
