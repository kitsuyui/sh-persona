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
git config --file "$profile_root/work/gitconfig" github.user example-user
git -C "$repo_dir" init -q
git -C "$repo_dir" config -f .gitmodules submodule.managed.path \
  repo/github.com/example/managed
git -C "$repo_dir" config persona.profile work
git -C "$repo_dir" config persona.githubUser example-user
git -C "$repo_dir" config persona.privateOnly true

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
  'repo view --json nameWithOwner,isPrivate,owner,viewerPermission')
    [ -z "${GH_REPO:-}" ] || exit 94
    printf \
      '{"nameWithOwner":"%s/repository","isPrivate":%s,"owner":{"login":"%s"},"viewerPermission":"%s"}\n' \
      "${FAKE_GH_OWNER:?}" \
      "${FAKE_GH_PRIVATE:?}" \
      "$FAKE_GH_OWNER" \
      "${FAKE_GH_PERMISSION:?}"
    ;;
  'api graphql '*)
    case "$*" in
    *'login=example-org'*) printf '%s\n' "${FAKE_GH_ORG_ADMIN:-true}" ;;
    *) printf '%s\n' false ;;
    esac
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
      FAKE_GH_PRIVATE="${FAKE_GH_PRIVATE:-true}" \
      FAKE_GH_OWNER="${FAKE_GH_OWNER:-someone-else}" \
      FAKE_GH_PERMISSION="${FAKE_GH_PERMISSION:-WRITE}" \
      "$PROJECT_ROOT/gh-persona" "$@"
  )
}

output=$(run_guard pr list)
grep -Fq "profile=$profile_root/work" <<<"$output"
grep -Fq 'repo=someone-else/repository' <<<"$output"
grep -Fq 'command=pr list' <<<"$output"

output=$(run_guard persona-status)
grep -Fq 'persona=work' <<<"$output"
grep -Fq 'github_user=example-user' <<<"$output"
grep -Fq 'verified=true' <<<"$output"

if FAKE_GH_USER=someone-else run_guard pr list >"$tmp_dir/wrong-user.out" 2>&1; then
  echo 'expected identity mismatch to fail' >&2
  exit 1
fi
grep -Fq 'identity mismatch' "$tmp_dir/wrong-user.out"

output=$(FAKE_GH_PRIVATE=false FAKE_GH_OWNER=example-user \
  FAKE_GH_PERMISSION=ADMIN run_guard pr list)
grep -Fq 'repo=example-user/repository' <<<"$output"

output=$(FAKE_GH_PRIVATE=false FAKE_GH_OWNER=Example-User \
  FAKE_GH_PERMISSION=ADMIN run_guard pr list)
grep -Fq 'repo=Example-User/repository' <<<"$output"

output=$(FAKE_GH_PRIVATE=false FAKE_GH_OWNER=example-org \
  FAKE_GH_PERMISSION=ADMIN run_guard pr comment 1 --body maintenance)
grep -Fq 'repo=example-org/repository' <<<"$output"

if FAKE_GH_PRIVATE=false FAKE_GH_OWNER=foreign-owner \
  FAKE_GH_PERMISSION=ADMIN run_guard pr list >"$tmp_dir/public-foreign.out" 2>&1; then
  echo 'expected a foreign public repository guard to fail' >&2
  exit 1
fi
grep -Fq 'public repository owner is not managed by this persona' \
  "$tmp_dir/public-foreign.out"

if FAKE_GH_PRIVATE=false FAKE_GH_OWNER=example-org FAKE_GH_ORG_ADMIN=false \
  FAKE_GH_PERMISSION=ADMIN run_guard pr list >"$tmp_dir/public-member.out" 2>&1; then
  echo 'expected organization membership without ownership to fail' >&2
  exit 1
fi
grep -Fq 'public repository owner is not managed by this persona' \
  "$tmp_dir/public-member.out"

if FAKE_GH_PRIVATE=false FAKE_GH_OWNER=example-org \
  FAKE_GH_PERMISSION=MAINTAIN run_guard pr list >"$tmp_dir/public-maintain.out" 2>&1; then
  echo 'expected non-admin permission to block public repository maintenance' >&2
  exit 1
fi
grep -Fq 'insufficient repository permission' "$tmp_dir/public-maintain.out"

if run_guard pr list -R example/other >"$tmp_dir/repo-override.out" 2>&1; then
  echo 'expected repository override to fail' >&2
  exit 1
fi
grep -Fq 'explicit repository selection is disabled' "$tmp_dir/repo-override.out"

git -C "$repo_dir" config persona.privateOnly false
if run_guard auth status --show-token >"$tmp_dir/public-token.out" 2>&1; then
  echo 'expected token output to fail for a public-enabled profile' >&2
  exit 1
fi
grep -Fq 'token output is disabled' "$tmp_dir/public-token.out"
git -C "$repo_dir" config persona.privateOnly true

for hub_command in \
  'auth status' \
  'search prs --owner example --limit 1000 --json number,url --state open' \
  'search issues --owner=example --limit=1000 --json=number,url' \
  'pr list --repo example/managed --state open --json url' \
  'repo list example --limit 1000 --json nameWithOwner' \
  'repo view example/managed --json nameWithOwner'; do
  read -r -a hub_args <<<"$hub_command"
  output=$(run_guard "${hub_args[@]}")
  grep -Fq "command=$hub_command" <<<"$output"
  grep -Fq 'repo= ' <<<"$output"
done

if FAKE_GH_PRIVATE=false FAKE_GH_OWNER=foreign-owner \
  run_guard auth status >"$tmp_dir/public-hub.out" 2>&1; then
  echo 'expected hub read-only mode from a public root to fail' >&2
  exit 1
fi
grep -Fq 'public repository owner is not managed by this persona' \
  "$tmp_dir/public-hub.out"

for unsafe_hub_command in \
  'search prs --owner someone-else --limit 1000 --json number,url' \
  'search prs --owner example unexpected-query' \
  'pr list --repo example/unmanaged' \
  'repo list someone-else' \
  'repo view example/unmanaged --json nameWithOwner'; do
  read -r -a unsafe_hub_args <<<"$unsafe_hub_command"
  if run_guard "${unsafe_hub_args[@]}" >"$tmp_dir/unsafe-hub.out" 2>&1; then
    printf 'expected unsafe hub command to fail: %s\n' "$unsafe_hub_command" >&2
    exit 1
  fi
  grep -Eq 'not allowed|arguments are disabled|explicit repository selection is disabled' \
    "$tmp_dir/unsafe-hub.out"
done

for unsafe_command in \
  'api repos/cli/cli' \
  'repo view cli/cli' \
  'repo create example --public' \
  'search repos example' \
  'auth status --show-token' \
  'issue transfer 1 example/public' \
  'label clone cli/cli'; do
  read -r -a unsafe_args <<<"$unsafe_command"
  if run_guard "${unsafe_args[@]}" >"$tmp_dir/unsafe-command.out" 2>&1; then
    printf 'expected unsafe command to fail: %s\n' "$unsafe_command" >&2
    exit 1
  fi
  grep -Eq 'not allowed|arguments are disabled|token output is disabled' \
    "$tmp_dir/unsafe-command.out"
done

git -C "$repo_dir" config --unset persona.profile
git -C "$repo_dir" config --unset persona.githubUser
git -C "$repo_dir" config --unset persona.privateOnly
git -C "$repo_dir" config gh.profile work
git -C "$repo_dir" config gh.user example-user
git -C "$repo_dir" config gh.private-only true
output=$(run_guard pr list)
grep -Fq 'command=pr list' <<<"$output"
git -C "$repo_dir" config --unset gh.profile
if run_guard pr list >"$tmp_dir/missing-profile.out" 2>&1; then
  echo 'expected missing profile to fail' >&2
  exit 1
fi
grep -Fq 'persona.profile is not configured' "$tmp_dir/missing-profile.out"
