#!/usr/bin/env bash
# Run formatting, linting, and behavior tests.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

tests/shellcheck.sh
tests/shfmt.sh
tests/persona-real-gh.sh
tests/git-persona.sh
tests/gh-persona.sh
tests/gh-persona-admin.sh
tests/persona-profile.sh
tests/persona.sh
