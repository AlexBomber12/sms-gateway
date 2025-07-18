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
| `MODEM_DEVICE` | Optional fixed modem device | `/dev/ttyUSB0` |
| `DEVICE` | *(legacy)* Path to the modem device | `/dev/ttyUSB0` |
| `BAUDRATE` | *(legacy)* Serial baud rate | `115200` |
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

## Fire-and-Forget Deployment
After starting, the container automatically searches for a Huawei modem and keeps
`gammu-smsd` running even if the USB port changes.

```bash
docker compose up -d
docker compose logs -f smsgateway
# look for “✅  Using modem …”
```

Run the container as root or add your user to `dialout` once:
```bash
sudo usermod -aG dialout $USER
```

You can optionally pin the modem with `MODEM_DEVICE=/dev/ttyUSB0`.
Stable names under `/dev/serial/by-id/` work out of the box, but you can also
create a custom udev rule if needed.

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

The CI pipeline runs these tests both on the host and again inside the built
Docker image. The image is only pushed if all tests succeed, ensuring you can
`docker pull` with confidence.

## CI / Tag release
The Docker image is published to GitHub Container Registry whenever a git tag is pushed.

**Secrets required**: none beyond the default `GITHUB_TOKEN`.

Release with:

```sh
git tag vX.Y.Z && git push --tags
```

For hardware-less pipelines set `CI_MODE=true` so the entrypoint exits if no modem is found.

## Troubleshooting
1. **Ports are visible on host?** `ls -l /dev/ttyUSB*`
2. **Port free?** `sudo fuser -v /dev/ttyUSB0`
3. **Modem responds?** `docker exec -it sms-gateway gammu -c /etc/gammu-smsdrc --identify`
4. **Service initialized?** `docker logs -f sms-gateway | tail`
5. **Message delivered to Telegram?** Check container logs for errors.
