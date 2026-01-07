Read and follow AGENTS.md strictly.

Goal: Fix CI failure where tests run under sudo and cannot import pytest, and optionally simplify CI by running tests only once (either host Python or Docker), while keeping behavior consistent.

Context:
- Current CI step runs: `sudo -E python -m pytest ...`
- Error: `/usr/bin/python: No module named pytest`
- Root cause: deps are installed for the non-sudo Python environment, but tests are executed under sudo using /usr/bin/python with a different site-packages.

Scope:
- Modify only GitHub Actions workflow files under .github/workflows/ (and scripts/run_tests.sh only if strictly needed).
- Do not change runtime application behavior.

Required changes:
1) Remove sudo from pytest execution:
- Replace `sudo -E python -m pytest ...` with `python -m pytest ...`.
- Ensure pytest is installed in the same interpreter environment used to run tests by installing via `python -m pip`.

2) Ensure dependency installation matches the interpreter:
- Use `actions/setup-python` with an explicit version (3.12).
- Install dependencies with:
  - `python -m pip install --upgrade pip`
  - `python -m pip install -r requirements.txt -r requirements-dev.txt`

3) Keep the existing test selection behavior:
- Preserve `-k "not test_detect_modem"` and `CI_MODE=true` (env var) exactly as before.

Optional improvement (choose one approach; implement only one, do not run tests twice):
A) Keep host-Python tests and remove Docker tests from CI:
- If the workflow also runs tests inside Docker, remove that duplicate step.
- Ensure host tests remain the single source of truth.

B) Keep Docker tests and remove host-Python tests from CI:
- Remove the host `python -m pytest` step entirely.
- Keep Docker-based test execution as the single source of truth.
- Ensure the Docker test command sets CI_MODE=true and excludes modem-dependent tests if needed.

If both host and Docker tests currently exist, pick option B (Docker-only) unless it would significantly slow CI or require privileged device access on runners.

Validation:
- Workflow passes on a PR branch.
- Confirm pytest is found and executed (no “No module named pytest”).
- Ensure tests are executed exactly once per workflow run.

Success criteria:
- CI no longer uses sudo for pytest.
- Dependencies and tests use the same Python interpreter.
- Tests run once and the workflow remains green.
