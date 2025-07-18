#!/usr/bin/env bash
set -euo pipefail

log() { echo "[start.sh] $*"; }

: "${DEVICE:?DEVICE variable is required}"
: "${BAUDRATE:?BAUDRATE variable is required}"
LOGLEVEL="${LOGLEVEL:-1}"

log "Starting with device $DEVICE baudrate $BAUDRATE"

mkdir -p /var/spool/gammu/{inbox,outbox,sent,error,archive}

if [ ! -f /etc/gammu-smsdrc ]; then
    log "Generating default smsdrc"
    cat > /etc/gammu-smsdrc <<EOF_CONF
[gammu]
device     = ${DEVICE}
connection = at
baudrate   = ${BAUDRATE}
logformat  = textalldate

[smsd]
service      = files
inboxpath    = /var/spool/gammu/inbox/
outboxpath   = /var/spool/gammu/outbox/
sentpath     = /var/spool/gammu/sent/
errorpath    = /var/spool/gammu/error/
RunOnReceive = python3 /app/on_receive.py
debuglevel   = ${LOGLEVEL}
logfile      = /dev/stdout
EOF_CONF
else
    log "Using existing smsdrc from volume"
fi

exec gammu-smsd -c /etc/gammu-smsdrc
