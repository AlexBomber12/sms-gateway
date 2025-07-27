#!/usr/bin/env bash
set -euo pipefail

CONTAINER="smsgateway"
VID="12d1"
PID="1506"

health=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "notfound")

if [[ "$health" == "unhealthy" ]]; then
  logger -t smsgw "watchdog: container unhealthy → resetting modem"
  usb_modeswitch -v "$VID" -p "$PID" -R  >/dev/null 2>&1 || true
  sleep 15
  docker restart "$CONTAINER"
fi
