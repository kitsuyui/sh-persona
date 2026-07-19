#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
profile_root="$tmp_dir/profiles"
profile_dir="$profile_root/example"
repo_dir="$tmp_dir/repo"
fake_gh="$tmp_dir/gh-real"

mkdir -p "$profile_dir" "$repo_dir"
touch "$profile_dir/hosts.yml"
git init -q "$repo_dir"
git config --file "$profile_dir/gitconfig" github.user example
git config --file "$profile_dir/gitconfig" user.name Example
git config --file "$profile_dir/gitconfig" user.email example@users.noreply.github.com
git config --file "$profile_dir/gitconfig" persona.signing false
printf 'Host example.github.com.invalid\n  HostName github.com\n  User git\n' \
  >"$profile_dir/ssh_config"

cat >"$fake_gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  'api user --jq .login') printf 'example\n' ;;
  *) exit 90 ;;
esac
EOF
chmod +x "$fake_gh"

(
  cd "$repo_dir"
  GH_PERSONA_PROFILE_ROOT="$profile_root" "$PROJECT_ROOT/persona" apply example
  GH_PERSONA_PROFILE_ROOT="$profile_root" \
    GH_PERSONA_REAL_GH="$fake_gh" \
    "$PROJECT_ROOT/persona" verify
  status=$(GH_PERSONA_PROFILE_ROOT="$profile_root" \
    GH_PERSONA_REAL_GH="$fake_gh" \
    "$PROJECT_ROOT/persona" status)
  grep -Fq 'github_user=example' <<<"$status"
  [ "$(GH_PERSONA_PROFILE_ROOT="$profile_root" "$PROJECT_ROOT/persona" list)" = example ]
)
