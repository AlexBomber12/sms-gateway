Read and follow AGENTS.md strictly.

Goal: Introduce pre-commit as the single source of truth for code quality gates (formatting and linting) and ensure these checks run on every PR and locally via scripts/run_tests.sh, so release workflows never fail late due to formatting or lint drift.

Motivation:
- The release workflow currently runs black --check (and possibly ruff) only on tags, which allowed formatting issues to slip through earlier checks.
- Pre-commit pins tool versions in .pre-commit-config.yaml and provides consistent local and CI behavior.

Scope:
- Add and configure pre-commit.
- Update existing CI workflows to run pre-commit on pull requests and main pushes.
- Update scripts/run_tests.sh to run the same checks locally.
- Do not change application runtime logic except what is required to satisfy the new checks.

Tasks:
1) Add pre-commit configuration:
- Add .pre-commit-config.yaml with pinned hooks for:
  - black (python formatting)
  - ruff (lint and optional ruff-format if desired, but avoid double-formatting with black)
  - end-of-file-fixer
  - trailing-whitespace
  - check-yaml
  - check-toml (if applicable)
  - check-added-large-files
  - detect-private-key
  - shellcheck (for *.sh files) if feasible via a local hook (see below)
- Keep it minimal and aligned with repo needs.

2) Dependencies and documentation:
- Add pre-commit to dev dependencies:
  - Prefer requirements-dev.txt or an existing dev requirements file.
  - Pin pre-commit version.
- Update README with short “Developer setup”:
  - pip install -r requirements-dev.txt
  - pre-commit install
  - pre-commit run --all-files
- Ensure no secrets are introduced.

3) CI integration (PR and main):
- Update the standard CI workflow (build.yml or equivalent) to run:
  - pip install -r requirements-dev.txt (or the correct dev deps)
  - pre-commit run --all-files
- Ensure this runs on pull_request and push to main.
- Ensure the release workflow reuses pre-commit:
  - Replace direct black --check steps with pre-commit run --all-files (or keep black step but make it redundant).
- Ensure CI remains fast and deterministic.

4) Local test script integration:
- Update scripts/run_tests.sh to run the same quality gates before tests:
  - pre-commit run --all-files
  - then pytest
- If scripts/run_tests.sh currently runs shellcheck separately, either:
  - Keep it, and do not duplicate shellcheck in pre-commit, or
  - Move shellcheck into pre-commit and remove the duplicate, but ensure shellcheck is still enforced everywhere.

5) Make files compliant:
- Run pre-commit hooks and apply needed formatting changes.
- Ensure black and ruff checks pass under the pinned versions.

Validation:
- pre-commit run --all-files
- scripts/run_tests.sh
- CI workflow passes on a PR branch.
- Release workflow passes when tagging (or at least will not newly fail due to formatting or lint).

Success criteria:
- A developer running scripts/run_tests.sh locally will catch the same formatting and lint issues that CI and release workflows enforce.
- CI on PR runs pre-commit and fails if formatting or lint is violated.
- Tool versions are pinned and stable over time (no surprise failures on tags).
- No secrets are added and no runtime behavior changes are introduced.
