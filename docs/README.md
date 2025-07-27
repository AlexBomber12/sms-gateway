# Documentation

## Modem watchdog
The image installs `/usr/local/bin/smsgw-watchdog.sh` and schedules it via `/etc/cron.d/smsgw-watchdog.cron`.
Every five minutes the script checks the health of the `smsgateway` container.
When it is reported as *unhealthy* the script detects the Huawei modem's current PID with `lsusb`, performs a soft USB reset and restarts the container.

To adapt to other Huawei models change the `VID` variable in the script. The PID is discovered automatically.
All output is appended to `/var/log/smsgw-watchdog.log` on the host.
