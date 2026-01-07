Read and follow AGENTS.md strictly.

Goal: Make the docker-compose configuration robust for MODEM_PORT=/dev/serial/by-id usage and improve modem stability after USB resets.

Context:
- Current compose file maps only /dev/ttyUSB0 and /dev/bus/usb and does not mount /dev/serial/by-id into the container. fileciteturn2file0
- On the host, the modem exposes stable symlinks under /dev/serial/by-id and multiple ttyUSB ports (ttyUSB0, ttyUSB1, ttyUSB2).
- The app supports MODEM_PORT, USB_VID, USB_PID and can perform USB reset via usb_modeswitch; for reliable resets the container needs /dev/bus/usb.
- If MODEM_PORT points to /dev/serial/by-id, the container must see that path and the underlying ttyUSB device nodes.

Scope:
- Modify docker-compose.yml (or the compose file used in production) and any related docs describing how to configure MODEM_PORT.
- Do not add any secrets.

Tasks:
1) Update the smsgateway service device and volume mappings:
- Keep /dev/bus/usb:/dev/bus/usb.
- Ensure the container can access stable serial symlinks:
  - Add bind mounts (read-only):
    - /dev/serial/by-id:/dev/serial/by-id:ro
    - /dev/serial/by-path:/dev/serial/by-path:ro
- Ensure the underlying ttyUSB device nodes exist inside the container:
  - Explicitly map /dev/ttyUSB0, /dev/ttyUSB1, /dev/ttyUSB2 as devices, or
  - If relying on privileged mode to expose all devices, verify inside the container that /dev/ttyUSB1 and /dev/ttyUSB2 and /dev/serial/by-id/* are present and usable. Prefer explicit mapping for determinism.

2) Revisit privileged mode and entrypoint override:
- If privileged is still required for usb reset, keep it.
- Verify the entrypoint path:
  - If the image already defines a correct ENTRYPOINT, remove the compose entrypoint override.
  - Otherwise, set entrypoint to the correct absolute path inside the image (exec-form preferred).

3) Clean up the compose file:
- Remove misleading comments like “others appear automatically” unless that is demonstrably true with current settings.
- Ensure the compose file remains minimal and copy-paste friendly.

4) Documentation:
- Update README or docs to include a short “Production recommended modem settings” section:
  - Recommend MODEM_PORT=/dev/serial/by-id/<device>
  - Mention that compose must mount /dev/serial/by-id and map the relevant ttyUSB devices.

Validation:
- Run: docker compose config
- Bring the stack up: docker compose up -d
- Verify inside the container:
  - ls -l /dev/serial/by-id
  - test -e /dev/ttyUSB0 and /dev/ttyUSB1 and /dev/ttyUSB2
- Verify logs show successful modem detection using the configured MODEM_PORT.
- Run scripts/run_tests.sh (if present) and ensure it exits with code 0.

Success criteria:
- Container can use MODEM_PORT pointing to /dev/serial/by-id without failing due to missing paths.
- USB reset continues to work (requires /dev/bus/usb access).
- Compose config is deterministic (no assumptions about devices “appearing automatically”).
- Docs reflect the actual recommended production setup.
