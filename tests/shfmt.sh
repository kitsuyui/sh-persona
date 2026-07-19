#!/usr/bin/env bash
# Check shell scripts are formatted with shfmt (2-space indent).
# Run `tests/shell-files.sh | xargs shfmt -i 2 -w` to apply the formatting.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

tests/shell-files.sh | xargs shfmt -i 2 -d
