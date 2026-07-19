#!/usr/bin/env bash
# Run formatting, linting, and behavior tests.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

run_check() {
  local name=$1
  shift
  printf '==> %s\n' "$name"
  "$@"
}

run_check shellcheck tests/shellcheck.sh
run_check shfmt tests/shfmt.sh
run_check persona-real-gh tests/persona-real-gh.sh
run_check git-persona tests/git-persona.sh
run_check gh-persona tests/gh-persona.sh
run_check gh-persona-admin tests/gh-persona-admin.sh
run_check persona-profile tests/persona-profile.sh
run_check persona tests/persona.sh
