#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fake_gh="$tmp_dir/gh-real"
profile_root="$tmp_dir/profiles"
repo_dir="$tmp_dir/repo"

mkdir -p "$profile_root/work" "$repo_dir"
touch "$profile_root/work/hosts.yml"
git -C "$repo_dir" init -q
git -C "$repo_dir" config persona.profile work
git -C "$repo_dir" config persona.githubUser example-user

cat >"$fake_gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ -z "${GH_TOKEN:-}" ] || exit 91
[ -z "${GITHUB_TOKEN:-}" ] || exit 92
[ "${GH_HOST:-}" = 'github.com' ] || exit 93

case "$*" in
  'api user --jq .login')
    printf '%s\n' "${FAKE_GH_USER:?}"
    ;;
  *)
    printf 'profile=%s repo=%s command=' "$GH_CONFIG_DIR" "${GH_REPO:-}"
    printf '%s ' "$@"
    printf '\n'
    ;;
esac
EOF
chmod +x "$fake_gh"

run_guard() {
  (
    cd "$repo_dir"
    GH_TOKEN=ambient-token \
      GH_REPO=example/ambient \
      GH_HOST=example.invalid \
      GH_PERSONA_REAL_GH="$fake_gh" \
      GH_PERSONA_PROFILE_ROOT="$profile_root" \
      FAKE_GH_USER="${FAKE_GH_USER:-example-user}" \
      "$PROJECT_ROOT/gh-persona" "$@"
  )
}

for allowed_command in \
  'pr list' \
  'pr list -R example/other' \
  'api repos/example/other' \
  'issue transfer 1 example/other' \
  'label clone example/other' \
  'search prs --owner example' \
  'auth status'; do
  read -r -a allowed_args <<<"$allowed_command"
  output=$(run_guard "${allowed_args[@]}")
  grep -Fq "profile=$profile_root/work" <<<"$output"
  grep -Fq 'repo= ' <<<"$output"
  grep -Fq "command=$allowed_command" <<<"$output"
done

output=$(run_guard persona-status)
grep -Fq 'persona=work' <<<"$output"
grep -Fq 'github_user=example-user' <<<"$output"
grep -Fq 'verified=true' <<<"$output"

if FAKE_GH_USER=someone-else run_guard pr list >"$tmp_dir/wrong-user.out" 2>&1; then
  echo 'expected identity mismatch to fail' >&2
  exit 1
fi
grep -Fq 'identity mismatch' "$tmp_dir/wrong-user.out"

for host_override in \
  'api --hostname example.invalid user' \
  'api --hostname=example.invalid user' \
  'auth status --host example.invalid'; do
  read -r -a host_args <<<"$host_override"
  if run_guard "${host_args[@]}" >"$tmp_dir/host-override.out" 2>&1; then
    printf 'expected host override to fail: %s\n' "$host_override" >&2
    exit 1
  fi
  grep -Fq 'explicit host selection is disabled' "$tmp_dir/host-override.out"
done

for unsafe_command in \
  'auth login' \
  'auth logout' \
  'auth refresh' \
  'auth setup-git' \
  'auth switch' \
  'auth token' \
  'auth status --show-token' \
  'config set editor vim' \
  'alias delete example' \
  'alias import aliases.yml' \
  'alias set example pr list' \
  'extension install example/extension' \
  'extension remove example' \
  'extension upgrade example'; do
  read -r -a unsafe_args <<<"$unsafe_command"
  if run_guard "${unsafe_args[@]}" >"$tmp_dir/unsafe-command.out" 2>&1; then
    printf 'expected unsafe command to fail: %s\n' "$unsafe_command" >&2
    exit 1
  fi
  grep -Eq 'mutation is disabled|token output is disabled' \
    "$tmp_dir/unsafe-command.out"
done

git -C "$repo_dir" config --unset persona.profile
git -C "$repo_dir" config --unset persona.githubUser
git -C "$repo_dir" config gh.profile work
git -C "$repo_dir" config gh.user example-user
output=$(run_guard pr list -R example/other)
grep -Fq 'command=pr list -R example/other' <<<"$output"
git -C "$repo_dir" config --unset gh.profile
if run_guard pr list >"$tmp_dir/missing-profile.out" 2>&1; then
  echo 'expected missing profile to fail' >&2
  exit 1
fi
grep -Fq 'persona.profile is not configured' "$tmp_dir/missing-profile.out"
