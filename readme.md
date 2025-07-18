# SMS Gateway → Telegram

This container forwards incoming SMS from a USB modem (tested with Huawei E352) to a Telegram chat. It should work with any modem supported by `gammu`.

## Environment variables
| Variable | Description | Example |
|----------|-------------|---------|
| `DEVICE` | Path to the modem device | `/dev/ttyUSB0` |
| `BAUDRATE` | Serial baud rate | `115200` |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token used for sending messages | `123:ABC` |
| `TELEGRAM_CHAT_ID` | Telegram chat ID that will receive messages | `123456` |
| `LOGLEVEL` | Optional gammu debug level (1..3) | `1` |

Copy `.env.example` to `.env` and fill in these values.

## Usage
### Option 1: pull ready image
```bash
docker pull ghcr.io/owner/sms-gateway:latest
cp .env.example .env
docker compose up -d
```

### Option 2: build locally
```bash
git clone https://github.com/owner/sms-gateway.git
cd sms-gateway
cp .env.example .env
docker compose up -d
# or for local testing
python3 on_receive.py
```

The container runs as root because USB devices usually require privileged access.

### Volumes
- `./state` → `/var/spool/gammu` – incoming/outgoing SMS and log files
- `./smsdrc` → `/etc/gammu-smsdrc` – override gammu configuration

## Troubleshooting
1. **Ports are visible on host?** `ls -l /dev/ttyUSB*`
2. **Port free?** `sudo fuser -v /dev/ttyUSB0`
3. **Modem responds?** `docker exec -it sms-gateway gammu -c /etc/gammu-smsdrc --identify`
4. **Service initialized?** `docker logs -f sms-gateway | tail`
5. **Message delivered to Telegram?** Check container logs for errors.
