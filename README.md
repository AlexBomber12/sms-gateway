# SMS Gateway → Telegram

This container forwards incoming SMS messages from a USB GSM modem to a Telegram chat.

## A. Requirements
- Docker and Docker Compose installed
- A compatible USB GSM modem (e.g., Huawei E353) connected and recognized (e.g., `/dev/ttyUSB0`)
- SIM card inserted and PIN unlocked

## B. Quick Start
1. Copy `.env.example` to `.env` and edit it (use `/dev/serial/by-id/...` for MODEM_PORT when possible; set `DELIVERY_MODE=queue` to enable buffered delivery):
   ```bash
   cp .env.example .env
   nano .env
   ```
2. Run the gateway:
   ```bash
   docker compose up -d
   docker logs -f smsgateway
   ```
   Expected logs:
   ```
   [entrypoint] ✅ Using pre-set /dev/ttyUSB0
   Starting phone communication...
   ```

## C. docker-compose.yml Notes
Ensure your `docker-compose.yml` includes:
```yaml
devices:
  - /dev/ttyUSB0:/dev/ttyUSB0
privileged: true
group_add:
  - dialout
```
These settings give the container access to the modem.

## D. Environment Variables
| Variable | Required | Description |
|---------|:-------:|-------------|
| MODEM_PORT | ✅ | e.g., `/dev/ttyUSB0`; device path of your modem |
| TELEGRAM_BOT_TOKEN | ✅ | Bot token used to forward messages |
| TELEGRAM_CHAT_ID | ✅ | Chat ID to receive forwarded messages |
| LOGLEVEL | ❌ | Python logging level: INFO, DEBUG, WARNING, etc. |
| GAMMU_DEBUGLEVEL | ❌ | Numeric gammu-smsd debuglevel (overrides numeric LOGLEVEL) |
| DELIVERY_MODE | ❌ | direct (default) or queue (enqueue + worker) |
| GAMMU_SPOOL_PATH | ❌ | Path for Gammu spool directories |
| MODEM_TIMEOUT_THRESHOLD | ❌ | Watchdog: timeouts before reset |
| RESET_MIN_INTERVAL | ❌ | Watchdog: min seconds between resets |
| RESET_BACKOFF_STEP | ❌ | Watchdog: backoff increment in seconds |
| RESET_BACKOFF_MAX | ❌ | Watchdog: max backoff in seconds |
| RESET_BACKOFF_WINDOW | ❌ | Watchdog: window for backoff accumulation |
| RESET_SETTLE_SECONDS | ❌ | Watchdog: wait after USB reset |
| USB_VID | ❌ | USB vendor ID for modem resets |
| USB_PID | ❌ | USB product ID for modem resets |

Precedence notes:
- `GAMMU_DEBUGLEVEL` overrides numeric `LOGLEVEL` for gammu-smsd; `LOGLEVEL` always controls Python logs.
- `USB_VID`/`USB_PID` override USB detection; otherwise `MODEM_PORT` is tried before `lsusb` scanning.

## E. Container Debugging & Manual Testing
```bash
# View logs
docker logs -f smsgateway

# Enter container
docker exec -it smsgateway /bin/sh

# Inspect modem devices
ls -l /dev/ttyUSB*

# Test manually
cat > /tmp/rc <<EOF_RC
[gammu]
device = /dev/ttyUSB0
connection = at
EOF_RC

gammu -c /tmp/rc identify
gammu -c /tmp/rc getallsms
```

## F. Troubleshooting
### Reading logs
- `docker logs -f smsgateway` or `docker compose logs -f smsgateway`
- Look for `[detect_modem]`, `[watchdog]`, and `gammu-smsd` lines for detection and resets

### Typical modem issues and auto-recovery
The watchdog counts timeout patterns (TIMEOUT, No response, etc.). After `MODEM_TIMEOUT_THRESHOLD`, it stops `gammu-smsd`, resets USB, waits `RESET_SETTLE_SECONDS`, and restarts detection. Frequent resets usually point to USB power, autosuspend, or ModemManager conflicts.

### Host hardening checklist
See `docs/host-setup.md` for stable `/dev/serial/by-id` paths, USB autosuspend rules, ModemManager guidance, and optional reset timer.

### Common symptoms
| Symptom | Cause | Fix |
|---------|-------|-----|
| No responsive modem | Invalid MODEM_PORT or modem not connected | Check `ls -l /dev/serial/by-id/` or `ls /dev/ttyUSB*` and update `.env` |
| you don't have the required permission | Missing `privileged: true` or `group_add` | Add both to `docker-compose.yml` |
| Unknown level: 'l' | Invalid LOGLEVEL value | Use `LOGLEVEL=INFO` or `DEBUG` |
| gammu-smsd exits or container restarts endlessly | Config or modem issue | Check logs and test with manual `gammu identify` |
| SMS received but not parsed | on_receive.py failure or incorrect spool path | Check logs and ensure `GAMMU_SPOOL_PATH` is correct |

Manual AT check (host):
```bash
echo -e "AT\r" | sudo socat - /dev/ttyUSB0,crnl
```
The correct response from the modem is "OK".

## G. Verification Steps
1. Tail logs and confirm modem detection and daemon start:
   ```
   [entrypoint] Starting modem detection
   [entrypoint] Starting sms-daemon
   ```
2. Send a test SMS to the modem number and look for:
   ```
   gammu-smsd: Received ...
   ```
3. If `DELIVERY_MODE=queue`, confirm the worker starts:
   ```
   [entrypoint] Starting queue worker
   ```

Optional inside the container:
```bash
gammu -c /tmp/gammu-smsdrc getallsms
```

## H. Modem Watchdog
The watchdog runs inside `entrypoint.sh`. It monitors `gammu-smsd` output for repeated timeout patterns, then stops `gammu-smsd`, resets the USB modem, waits for it to settle, and restarts modem detection. Resets use `usb_modeswitch` when available and can rebind the USB device via sysfs.

Watchdog tuning is available via `MODEM_TIMEOUT_THRESHOLD` and the `RESET_*` backoff variables. USB detection can be overridden with `USB_VID` and `USB_PID`, otherwise it is derived from `MODEM_PORT` or `lsusb`.

## I. Upgrade Notes
- `DELIVERY_MODE=direct` remains the default; set `DELIVERY_MODE=queue` to enable durable, buffered delivery via the queue worker.
- `GAMMU_DEBUGLEVEL` now controls gammu-smsd debug output; numeric `LOGLEVEL` is still accepted as a fallback.
- Watchdog tuning envs are now documented in `.env.example` (`MODEM_TIMEOUT_THRESHOLD`, `RESET_*`) to adjust recovery timing.
- For more stable deployments, prefer `/dev/serial/by-id` for `MODEM_PORT` and review `docs/host-setup.md`.

## J. Dependencies
All required dependencies are installed automatically via Dockerfile:
- gammu
- gammu-smsd
- usb-modeswitch
- socat
