#!/usr/bin/env bash
set -euo pipefail

USB_VID="${USB_VID:-12d1}"
USB_PID="${USB_PID:-1506}"
RESET_SETTLE_SECONDS="${RESET_SETTLE_SECONDS:-15}"

if ! command -v usb_modeswitch >/dev/null 2>&1; then
  echo "usb_modeswitch not found; install it or adjust this script." >&2
  exit 1
fi

usb_modeswitch -v "$USB_VID" -p "$USB_PID" -R >/dev/null 2>&1 || true
sleep "$RESET_SETTLE_SECONDS"
