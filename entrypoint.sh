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
# ------------------------------------------------------------------
# 1. build candidate list
CANDIDATES=()
[ -n "${MODEM_PORT}" ] && CANDIDATES+=("${MODEM_PORT}")
CANDIDATES+=(/dev/serial/by-id/* /dev/ttyUSB*)

# 2. probe each candidate
for DEV in "${CANDIDATES[@]}"; do
  [ -e "${DEV}" ] || continue

  # create minimal config for the probe
  cat > /tmp/gammurc <<EOF
[gammu]
device = ${DEV}
connection = at
EOF

  # give up after 12 s if no reply
  if timeout 12 gammu --config /tmp/gammurc identify >/dev/null 2>&1; then
    echo "✅ Using modem ${DEV}"

    # full config for smsd
    cat > /tmp/gammu-smsdrc <<EOF
[gammu]
device = ${DEV}
connection = at

[smsd]
service = files
EOF

    exec gammu-smsd -c /tmp/gammu-smsdrc -f
  fi
done

echo "❌ No responsive modem found"
exit 1
# ------------------------------------------------------------------
