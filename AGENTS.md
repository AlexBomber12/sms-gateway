# Agent Workflow Rules

- Source of truth for work items is `tasks/PR-XX.md`.
- Create a branch named `pr-xx-short-title` (lowercase, hyphen-separated) for each task.
- Run `bash scripts/run_tests.sh` locally before committing.
- To stream test output live, run `VERBOSE=1 bash scripts/run_tests.sh`.
- Only commit when `scripts/run_tests.sh` exits with code 0.
- Push the branch to `origin` after tests are green.
- Never commit secrets; `.env` must not be committed.
- Keep diffs minimal and within the task scope.
- Write concise commit messages with the PR id prefix, e.g. `PR-00: agent workflow foundation`.
