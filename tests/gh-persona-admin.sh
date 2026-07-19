#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
tmp_dir=$(mktemp -d)
profile_root="$tmp_dir/profiles"
profile_dir="$profile_root/work"
default_dir="$tmp_dir/default-gh"
fake_gh="$tmp_dir/gh-real"

cleanup() {
  chflags -R nouchg "$tmp_dir" 2>/dev/null || true
  chmod -R u+w "$tmp_dir" 2>/dev/null || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$profile_dir" "$default_dir"
touch "$profile_dir/config.yml" "$profile_dir/hosts.yml" "$default_dir/hosts.yml"

cat >"$fake_gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ "$*" = 'api user --jq .login' ] || exit 90
printf 'example-user\n'
EOF
chmod +x "$fake_gh"

run_admin() {
  GH_PERSONA_PROFILE_ROOT="$profile_root" \
    GH_PERSONA_DEFAULT_CONFIG_DIR="$default_dir" \
    GH_PERSONA_REAL_GH="$fake_gh" \
    "$PROJECT_ROOT/gh-persona-admin" "$@"
}

run_admin status work example-user
run_admin lock work
[ "$(stat -f '%Lp' "$profile_dir/config.yml" 2>/dev/null || stat -c '%a' "$profile_dir/config.yml")" = 600 ]
run_admin unlock work

output=$(run_admin seal-default)
grep -Fq 'sealed default config; recoverable backup:' <<<"$output"
[ -f "$default_dir" ]
grep -Fq 'intentionally disabled' "$default_dir"
[ "$(find "$profile_root" -maxdepth 1 -type d -name 'default-backup-*' | wc -l | tr -d ' ')" = 1 ]
