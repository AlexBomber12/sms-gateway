# Host setup for USB modem stability

This guide covers host-level hardening steps to reduce USB modem dropouts on Linux servers. Apply these before chasing container or application changes.

## 1) Identify the modem and stable device path

1. Plug in the modem and list stable symlinks:
   ```bash
   ls -l /dev/serial/by-id/
   ```
2. Pick the symlink that matches your modem (example: `/dev/serial/by-id/usb-HUAWEI_Mobile-if00-port0`).
3. Capture vendor/product IDs:
   ```bash
   lsusb
   ```
   Look for your modem and note `idVendor:idProduct` (example: `12d1:1506`).

## 2) Use `/dev/serial/by-id` for MODEM_PORT

Set `MODEM_PORT` to the `/dev/serial/by-id/...` path so reboots or USB re-enumeration do not change the device name. This is more stable than `/dev/ttyUSB0`.

## 3) Disable USB autosuspend for the modem

1. Copy the udev rule template from this repo:
   ```bash
   sudo cp scripts/host/99-sms-gateway-modem-power.rules /etc/udev/rules.d/
   ```
2. Edit the rule and replace `idVendor` and `idProduct` with your values from `lsusb`:
   ```bash
   sudo nano /etc/udev/rules.d/99-sms-gateway-modem-power.rules
   ```
3. Reload udev rules and replug the modem (or trigger udev):
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```
4. Optional verification (should print `on`):
   ```bash
   cat "/sys$(udevadm info -q path -n /dev/serial/by-id/<your-id>)/power/control"
   ```

## 4) ModemManager options

ModemManager often grabs USB modems and can interfere with Gammu. Choose one approach:

### Option A: Disable ModemManager globally (simplest)

```bash
sudo systemctl disable --now ModemManager
```

Tradeoff: all ModemManager functionality is disabled, which can impact other cellular devices on the host.

### Option B: Ignore only this modem via udev tagging

Create a udev rule that tells ModemManager to ignore the specific device:

```
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", ATTR{idProduct}=="1506", ENV{ID_MM_DEVICE_IGNORE}="1"
```

Save it as `/etc/udev/rules.d/99-sms-gateway-modemmanager.rules`, then reload udev rules:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Tradeoffs: you must match the correct device identifiers, and some modems present multiple USB IDs during mode switching, which may require additional rules. A bad match can ignore the wrong device.

## 5) Optional: systemd reset timer (second layer)

If dropouts persist even after the steps above, you can add a host-level reset timer as a fallback. This is optional and can disrupt active sessions; use sparingly.

Ensure `usb_modeswitch` is installed on the host (package names vary by distro, e.g. `usb-modeswitch` on Debian/Ubuntu).

1. Install the reset script and adjust VID/PID if needed:
   ```bash
   sudo cp scripts/host/sms-gateway-modem-reset.sh /usr/local/sbin/
   sudo chmod +x /usr/local/sbin/sms-gateway-modem-reset.sh
   sudo nano /usr/local/sbin/sms-gateway-modem-reset.sh
   ```
2. Install the systemd unit files:
   ```bash
   sudo cp scripts/host/sms-gateway-modem-reset.service /etc/systemd/system/
   sudo cp scripts/host/sms-gateway-modem-reset.timer /etc/systemd/system/
   ```
3. Update `USB_VID`/`USB_PID` in `/etc/systemd/system/sms-gateway-modem-reset.service` (or use a drop-in override).
4. Enable the timer:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now sms-gateway-modem-reset.timer
   ```
5. Manual test:
   ```bash
   sudo systemctl start sms-gateway-modem-reset.service
   ```

## 6) Hardware and power notes

- Prefer a powered USB hub, especially on small servers or SBCs with limited USB power.
- Use short, shielded cables and avoid loose connectors or front-panel ports.
- Keep the modem on a dedicated port when possible.
- Avoid host sleep/hibernate features on servers.
