#!/usr/bin/env bash
set -euo pipefail
mkdir -p /var/spool/gammu/{inbox,outbox,sent,error,archive}

chmod +x /app/on_receive.py

cat > /etc/gammu-smsdrc <<EOF
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
debuglevel   = 1
logfile      = /dev/stdout
EOF

exec gammu-smsd -c /etc/gammu-smsdrc
