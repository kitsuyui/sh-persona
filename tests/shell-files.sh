#!/usr/bin/env bash
# Print tracked shell scripts, one path per line.
#
# sh-persona keeps extensionless executables directly in the repository root,
# so shell scripts are selected by their shebang rather than by file extension.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

git ls-files --cached --others --exclude-standard | while IFS= read -r file; do
  [ -f "$file" ] || continue
  if head -n1 "$file" | grep -qE '^#!.*\b(ba|da|k|a)?sh\b'; then
    printf '%s\n' "$file"
  fi
done
