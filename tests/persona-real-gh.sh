#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
foreign_guard="$tmp_dir/foreign/gh-guard-bin"
real_bin="$tmp_dir/real-bin"
mkdir -p "$foreign_guard" "$real_bin"
real_bin=$(CDPATH='' cd -- "$real_bin" && pwd -P)

for executable in "$foreign_guard/gh" "$real_bin/gh"; do
  printf '#!/bin/sh\nexit 0\n' >"$executable"
  chmod +x "$executable"
done

resolved=$(PATH="$foreign_guard:$PROJECT_ROOT/gh-guard-bin:$real_bin:$PATH" \
  "$PROJECT_ROOT/libexec/persona-real-gh")
[ "$resolved" = "$real_bin/gh" ]
