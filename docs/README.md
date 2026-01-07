# Documentation

## Modem watchdog
The modem watchdog is built into `entrypoint.sh`. It starts `gammu-smsd`, watches its output, and looks for consecutive timeout patterns. Once the threshold is reached it stops `gammu-smsd`, resets the USB modem, waits for it to settle, and restarts modem detection.

The reset sequence uses `usb_modeswitch` when available and optionally rebinds the USB device via sysfs. The watchdog applies a backoff window to avoid reset storms.

Configuration options:
- `MODEM_TIMEOUT_THRESHOLD` (default: 3)
- `RESET_MIN_INTERVAL` (default: 60)
- `RESET_BACKOFF_STEP` (default: 30)
- `RESET_BACKOFF_MAX` (default: 300)
- `RESET_BACKOFF_WINDOW` (default: 300)
- `RESET_SETTLE_SECONDS` (default: 20)
- `USB_VID` and `USB_PID` override USB detection; otherwise detection uses `MODEM_PORT` or `lsusb`.

Check container logs for `[watchdog]` lines to confirm behavior.

## Runtime logs
Entrypoint logs are prefixed with `[entrypoint]`. Modem probing uses `[detect_modem]`, and watchdog activity uses `[watchdog]`.

## Healthcheck behavior
The container healthcheck is non-intrusive: it checks for `/tmp/gammu-smsdrc` and a running `gammu-smsd` process, without probing the modem.

## Windows ADS artifacts
Windows can create NTFS Alternate Data Stream files like `*:Zone.Identifier` during downloads or extraction. These are ignored in `.gitignore` to avoid cross-platform checkout issues.
