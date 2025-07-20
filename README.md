# SMS Gateway → Telegram

This container forwards incoming SMS messages from a USB GSM modem to a Telegram chat.

## A. Requirements
- Docker and Docker Compose installed
- A compatible USB GSM modem (e.g., Huawei E353) connected and recognized (e.g., `/dev/ttyUSB0`)
- SIM card inserted and PIN unlocked

## B. Quick Start
1. Copy `.env.example` to `.env` and edit it:
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
| LOGLEVEL | ❌ | Logging level: INFO, DEBUG, WARNING, etc. |
| GAMMU_SPOOL_PATH | ❌ | Path for Gammu spool directories |

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
| Symptom | Cause | Fix |
|---------|-------|-----|
| No responsive modem | Invalid MODEM_PORT or modem not connected | Check `ls /dev/ttyUSB*` and update `.env` |
| you don't have the required permission | Missing `privileged: true` or `group_add` | Add both to `docker-compose.yml` |
| Unknown level: 'l' | Invalid LOGLEVEL value | Use `LOGLEVEL=INFO` or `DEBUG` |
| gammu-smsd exits or container restarts endlessly | Config or modem issue | Check logs and test with manual `gammu identify` |
| SMS received but not parsed | on_receive.py failure or incorrect spool path | Check logs and ensure `GAMMU_SPOOL_PATH` is correct |

## G. Confirming SMS Reception
Check logs for messages:
```
gammu-smsd: Received ...
```
Or run inside the container:
```bash
gammu -c /tmp/gammu-smsdrc getallsms
```
