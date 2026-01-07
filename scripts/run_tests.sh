#!/usr/bin/env bash
set -e
set -u
set -o pipefail

ARTEFACTS_DIR="artefacts"
KEEP_COUNT="${ARTEFACTS_KEEP:-20}"
VERBOSE="${VERBOSE:-0}"

mkdir -p "${ARTEFACTS_DIR}"

timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
run_dir="${ARTEFACTS_DIR}/run-${timestamp}"
if [[ -e "${run_dir}" ]]; then
  suffix=1
  while [[ -e "${run_dir}-${suffix}" ]]; do
    suffix=$((suffix + 1))
  done
  run_dir="${run_dir}-${suffix}"
fi

mkdir -p "${run_dir}"

export CI_MODE=true

pytest_log="${run_dir}/pytest.log"
shellcheck_log="${run_dir}/shellcheck.log"
summary_log="${run_dir}/summary.txt"
PYTEST_TIMEOUT="${PYTEST_TIMEOUT:-240}"

run_check() {
  local name="$1"
  local log_file="$2"
  shift 2

  local rc=0
  if [[ "${VERBOSE}" == "1" ]]; then
    echo "==> ${name}"
    set +e
    "$@" 2>&1 | tee "${log_file}"
    rc=${PIPESTATUS[0]}
    set -e
  else
    set +e
    "$@" >"${log_file}" 2>&1
    rc=$?
    set -e
  fi

  return "${rc}"
}

pytest_exit=0
pytest_timed_out=0
if command -v timeout >/dev/null 2>&1; then
  run_check "pytest" "${pytest_log}" timeout "${PYTEST_TIMEOUT}"s python -m pytest -q || pytest_exit=$?
  if [[ ${pytest_exit} -eq 124 ]]; then
    pytest_timed_out=1
    echo "PYTEST_TIMEOUT after ${PYTEST_TIMEOUT}s" >>"${pytest_log}"
  fi
else
  run_check "pytest" "${pytest_log}" python -m pytest -q || pytest_exit=$?
fi

shellcheck_exit=0
shellcheck_files=()
for file in entrypoint.sh start.sh smsgw-watchdog.sh; do
  if [[ -f "${file}" ]]; then
    shellcheck_files+=("${file}")
  fi
done

if [[ -d scripts ]]; then
  shopt -s nullglob
  for file in scripts/*.sh; do
    shellcheck_files+=("${file}")
  done
  shopt -u nullglob
fi

if [[ ${#shellcheck_files[@]} -eq 0 ]]; then
  echo "No shell scripts found for shellcheck." >"${shellcheck_log}"
else
  run_check "shellcheck" "${shellcheck_log}" shellcheck "${shellcheck_files[@]}" || shellcheck_exit=$?
fi

{
  echo "pytest_exit=${pytest_exit}"
  echo "pytest_timeout=${pytest_timed_out}"
  echo "shellcheck_exit=${shellcheck_exit}"
} >"${summary_log}"

if ln -sfn "$(basename "${run_dir}")" "${ARTEFACTS_DIR}/latest" 2>/dev/null; then
  rm -f "${ARTEFACTS_DIR}/latest.txt" 2>/dev/null || true
else
  echo "${run_dir}" >"${ARTEFACTS_DIR}/latest.txt"
fi

if [[ "${KEEP_COUNT}" =~ ^[0-9]+$ ]]; then
  mapfile -t runs < <(ls -1dt "${ARTEFACTS_DIR}"/run-* 2>/dev/null || true)
  if (( ${#runs[@]} > KEEP_COUNT )); then
    for ((i=KEEP_COUNT; i<${#runs[@]}; i++)); do
      rm -rf "${runs[$i]}"
    done
  fi
fi

if (( pytest_exit != 0 || shellcheck_exit != 0 )); then
  exit 1
fi

exit 0
