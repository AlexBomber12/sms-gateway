#!/usr/bin/env bash
set -euo pipefail

# ---- 0. Immediate bypasses ---------------------------------------------
# Skip the modem scan entirely during CI or when explicitly requested. If a
# command is supplied it is executed before exiting.
if [[ "${CI_MODE:-}" == "true" || "${SKIP_MODEM:-}" == "true" ]]; then
  echo "[entrypoint] Modem scan disabled."
  [[ $# -gt 0 ]] && exec "$@"
  exit 0
fi

# ---- 1. Normal production path (modem auto-scan once) -------------------

log(){ echo "[entrypoint] $*"; }

LOGLEVEL="${LOGLEVEL:-1}"
GAMMU_SPOOL_PATH="${GAMMU_SPOOL_PATH:-/var/spool/gammu}"

mkdir -p "$GAMMU_SPOOL_PATH"/{inbox,outbox,sent,error,archive}

# ---- 2. Detect modem ----------------------------------------------------
if [ -n "${MODEM_PORT:-}" ]; then
    CANDIDATES=("${MODEM_PORT}")
else
    CANDIDATES=(/dev/serial/by-id/* /dev/ttyUSB*)
fi

MODEM_DEV=""
for DEV in "${CANDIDATES[@]}"; do
    [ -e "$DEV" ] || continue
    cat > /tmp/gammurc <<EOF
[gammu]
device = $DEV
connection = at
EOF
    if timeout 3 gammu --config /tmp/gammurc identify >/dev/null 2>&1; then
        log "✅ Using modem $DEV"
        MODEM_DEV="$DEV"
        break
    fi
done

if [ -z "$MODEM_DEV" ]; then
    log "❌ No responsive modem found"
    exit 1
fi

# ---- 3. Generate SMSD configuration ------------------------------------
cat > /tmp/gammu-smsdrc <<EOF
[gammu]
device = $MODEM_DEV
connection = at

[smsd]
service = files
EOF

exec gammu-smsd -c /tmp/gammu-smsdrc -f
