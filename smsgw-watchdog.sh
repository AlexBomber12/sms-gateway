#!/usr/bin/env bash
set -euo pipefail

CONTAINER="smsgateway"
VID="12d1"                            # Huawei vendor
PID=$(lsusb -d ${VID}: | awk '{print $6}' | head -n1 | cut -d: -f2)

if [[ -z "$PID" ]]; then
  logger -t smsgw "watchdog: no Huawei device found, skipping"
  exit 0
fi

health=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "notfound")

if [[ "$health" == "unhealthy" ]]; then
  logger -t smsgw "watchdog: container unhealthy, resetting modem ${VID}:${PID}"
  usb_modeswitch -v "$VID" -p "$PID" -R >/dev/null 2>&1 || true
  sleep 15
  docker restart "$CONTAINER"
fi
