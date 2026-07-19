#!/usr/bin/env bash
# Lint shell scripts with shellcheck.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

tests/shell-files.sh | xargs shellcheck
