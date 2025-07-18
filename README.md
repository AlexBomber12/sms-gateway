# SMS Gateway → Telegram

This project provides a simple gateway that forwards incoming SMS messages from a USB modem to a Telegram chat using `gammu`.

## Quickstart
1. Pull the image from GitHub Container Registry
   ```sh
   docker pull ghcr.io/owner/sms-gateway:latest
   ```
2. Copy the example environment file and edit it
   ```sh
   cp .env.example .env
   # edit .env with your values
   ```
3. Start the service
   ```sh
   docker compose up -d
   ```

For local testing without root, you can set:
```sh
export GAMMU_SPOOL_PATH=/tmp/gammu-spool
export GAMMU_CONFIG_PATH=/tmp/smsdrc
```

## Environment variables
| Variable | Description | Example |
|----------|-------------|---------|
| `DEVICE` | Path to the modem device | `/dev/ttyUSB0` |
| `BAUDRATE` | Serial baud rate | `115200` |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token used for sending messages | `123:ABC` |
| `TELEGRAM_CHAT_ID` | Telegram chat ID that will receive messages | `123456` |
| `LOGLEVEL` | Optional gammu debug level (1..3) | `1` |
| `GAMMU_SPOOL_PATH` | Path used for gammu spool directories | `/var/spool/gammu` |
| `GAMMU_CONFIG_PATH` | Path to generated smsdrc file | `/etc/gammu-smsdrc` |

Copy `.env.example` to `.env` and fill in these values before starting the container.

## Usage
### Build locally
```bash
git clone https://github.com/owner/sms-gateway.git
cd sms-gateway
cp .env.example .env
docker compose up -d
```

The container runs as root because USB devices usually require privileged access.

### Volumes
- `./state` → `/var/spool/gammu` – incoming/outgoing SMS and log files
- `./smsdrc` → `/etc/gammu-smsdrc` – override gammu configuration

## Running Tests Locally
Install dependencies and run the test suite (no root needed):
```sh
pip install -r requirements.txt
GAMMU_SPOOL_PATH=/tmp/gammu-test \
GAMMU_CONFIG_PATH=/tmp/gammu-smsdrc \
python -m unittest discover -s tests -v
```

## Troubleshooting
1. **Ports are visible on host?** `ls -l /dev/ttyUSB*`
2. **Port free?** `sudo fuser -v /dev/ttyUSB0`
3. **Modem responds?** `docker exec -it sms-gateway gammu -c /etc/gammu-smsdrc --identify`
4. **Service initialized?** `docker logs -f sms-gateway | tail`
5. **Message delivered to Telegram?** Check container logs for errors.
