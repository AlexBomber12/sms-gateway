Read and follow AGENTS.md strictly.

Goal: Final cleanup pass to eliminate remaining release and CI inconsistencies, make pre-commit the single source of truth across local + CI + release, and improve troubleshooting docs for the /dev/serial mounts issue.

Context:
- Repo has a pinned .pre-commit-config.yaml but CI and local scripts are not consistently using it.
- build.yml does not run pre-commit, and package.yml still installs ruff/black directly (unpinned) instead of using pre-commit (pinned), which can reintroduce “fails only on tags” incidents.
- scripts/run_tests.sh does not run pre-commit, so developers can still miss formatting/lint issues until release.
- Makefile `lint` target still runs ruff/black directly, bypassing pinned hook versions.
- A real-world issue occurred: MODEM_PORT pointed to /dev/serial/by-id/... but the container did not have /dev/serial mounted due to using a different compose file. This should be explicitly documented in Troubleshooting.

Scope:
- Update CI workflows to run pre-commit.
- Update scripts/run_tests.sh and Makefile to use pre-commit.
- Improve .pre-commit-config.yaml to include basic hygiene/security hooks.
- Update docs (README.md and/or docs/README.md) to include the missing /dev/serial mount troubleshooting case.
- Do not change runtime behavior of the gateway except as required to satisfy the new checks.

Tasks:
1) Make pre-commit the authoritative gate (local):
- Update scripts/run_tests.sh:
  - Run `pre-commit run --all-files` before pytest and shellcheck.
  - If pre-commit is not installed, fail with a clear message.
- Update Makefile:
  - Change `lint` target to run `pre-commit run --all-files` instead of invoking ruff/black directly.
- Optional: if shellcheck is already enforced by scripts/run_tests.sh and CI, do not duplicate shellcheck in pre-commit unless you also remove the separate shellcheck step. Keep exactly one source of truth for shellcheck.

2) Update .pre-commit-config.yaml (pinned versions):
- Add the official pre-commit-hooks repo with at least:
  - trailing-whitespace
  - end-of-file-fixer
  - check-yaml
  - check-toml (only if TOML files exist)
  - check-added-large-files
  - detect-private-key
- Keep existing pinned hooks:
  - ruff (astral-sh/ruff-pre-commit)
  - black (psf/black)
  - yamllint (adrienverge/yamllint)
- For black:
  - Prefer allowing it to format (remove --check) so pre-commit can auto-fix locally.
  - CI will still fail if files are not formatted because pre-commit will modify and exit non-zero.
  - If you keep --check, document how to fix (run black) in README; but the preferred approach is auto-fix.

3) CI: run pre-commit on every PR and on main pushes:
- Update .github/workflows/build.yml:
  - Add actions/setup-python with an explicit version (use 3.12 to match the Docker base image).
  - Install deps (requirements.txt + requirements-dev.txt).
  - Run `pre-commit run --all-files` as a dedicated step before tests.
  - Remove any redundant format/lint steps that are now covered by pre-commit (keep shellcheck action if you did not add shellcheck hook).
- Ensure CI still runs unit tests with CI_MODE=true and continues to skip any modem-dependent tests as before.

4) Release workflow: use pre-commit instead of unpinned direct tools:
- Update .github/workflows/package.yml:
  - Replace the current lint job (pip install ruff black; ruff check; black --check) with:
    - pip install -r requirements-dev.txt (or at least pip install pre-commit)
    - pre-commit run --all-files
  - This ensures the same pinned versions and rules as local and PR CI.

5) Documentation: add the missing /dev/serial mount troubleshooting case:
- In README.md Troubleshooting (table or a short subsection), add:
  - Symptom: MODEM_PORT=/dev/serial/by-id/... but inside container /dev/serial/by-id is missing (ls fails).
  - Cause: container not started with the compose file that mounts /dev/serial, or compose changes were not applied (container not recreated).
  - Fix:
    - Verify mounts: `docker inspect smsgateway --format '{{range .Mounts}}{{println .Destination " <- " .Source}}{{end}}' | sort`
    - Verify actual compose being used: `docker inspect smsgateway --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'` and `...config_files`
    - Recreate: `docker compose up -d --force-recreate`
- Keep the troubleshooting text short and copy-paste friendly.

Validation:
- pre-commit run --all-files
- scripts/run_tests.sh
- make lint
- docker compose config
- CI build workflow passes
- Release workflow lint job uses pre-commit (no direct unpinned ruff/black)

Success criteria:
- The same checks run locally (scripts/run_tests.sh, make lint), on PR CI (build.yml), and on release tags (package.yml), using pinned pre-commit hook versions.
- No more “format/lint failures only on tag” incidents.
- Troubleshooting explicitly covers the /dev/serial/by-id mount mismatch scenario and how to verify it.
