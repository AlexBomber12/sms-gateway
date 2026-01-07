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
precommit_log="${run_dir}/pre-commit.log"
summary_log="${run_dir}/summary.txt"
PYTEST_TIMEOUT="${PYTEST_TIMEOUT:-240}"

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "pre-commit is required but not installed. Install with 'pip install -r requirements-dev.txt'." | tee "${precommit_log}" >&2
  {
    echo "precommit_exit=127"
    echo "pytest_exit=0"
    echo "pytest_timeout=0"
  } >"${summary_log}"
  exit 1
fi

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
precommit_exit=0
run_check "pre-commit" "${precommit_log}" pre-commit run --all-files || precommit_exit=$?

if command -v timeout >/dev/null 2>&1; then
  run_check "pytest" "${pytest_log}" timeout "${PYTEST_TIMEOUT}"s python -m pytest -q || pytest_exit=$?
  if [[ ${pytest_exit} -eq 124 ]]; then
    pytest_timed_out=1
    echo "PYTEST_TIMEOUT after ${PYTEST_TIMEOUT}s" >>"${pytest_log}"
  fi
else
  run_check "pytest" "${pytest_log}" python -m pytest -q || pytest_exit=$?
fi

{
  echo "precommit_exit=${precommit_exit}"
  echo "pytest_exit=${pytest_exit}"
  echo "pytest_timeout=${pytest_timed_out}"
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

if (( precommit_exit != 0 || pytest_exit != 0 )); then
  exit 1
fi

exit 0
