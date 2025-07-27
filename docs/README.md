# Documentation

## Modem watchdog
The image installs `/usr/local/bin/smsgw-watchdog.sh` and schedules it via `/etc/cron.d/smsgw-watchdog.cron`.
Every five minutes the script checks the health of the `smsgateway` container.
When it is reported as *unhealthy* the script performs a soft USB reset using:

```bash
usb_modeswitch -v 12d1 -p 1506 -R
```

After waiting 15&nbsp;seconds for the modem to reappear the container is restarted.
To use a different modem change the `VID` and `PID` variables at the top of the script.
All output is appended to `/var/log/smsgw-watchdog.log` on the host.
