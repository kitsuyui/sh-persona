#!/usr/bin/env bash
# shellcheck disable=SC2088 # verify literal ~/.ssh values in generated SSH config.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
tmp_dir=$(mktemp -d)
profile_root="$tmp_dir/profiles"
profile_dir="$profile_root/work"
fake_gh="$tmp_dir/gh-real"

cleanup() {
  chflags -R nouchg "$tmp_dir" 2>/dev/null || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$profile_dir"
touch "$profile_dir/hosts.yml"

cat >"$fake_gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ "$1 $2 $3" = 'api /user --jq' ] || exit 90
printf '%s\t%s\t%s\n' \
  "${FAKE_GH_USER:-example-user}" \
  "${FAKE_GH_ID:-123}" \
  "${FAKE_GH_EMAIL:-}"
EOF
chmod +x "$fake_gh"

run_profile() {
  GH_PERSONA_PROFILE_ROOT="$profile_root" \
    GH_PERSONA_REAL_GH="$fake_gh" \
    "$PROJECT_ROOT/persona-profile" "$@"
}

run_profile sync work
[ "$(git config --file "$profile_dir/gitconfig" --get github.user)" = example-user ]
[ "$(git config --file "$profile_dir/gitconfig" --get user.email)" = \
  123+example-user@users.noreply.github.com ]
[ "$(git config --file "$profile_dir/gitconfig" --bool --get persona.signing)" = false ]
if git config --file "$profile_dir/gitconfig" --get persona.privateOnly >/dev/null; then
  echo 'expected repository authorization policy to be absent from the persona' >&2
  exit 1
fi
grep -Fq 'Host example-user.github.com.invalid' "$profile_dir/ssh_config"
grep -Fq 'HostName github.com' "$profile_dir/ssh_config"
run_profile verify work
[ "$(run_profile list)" = work ]

chflags nouchg "$profile_dir/gitconfig" 2>/dev/null || true
git config --file "$profile_dir/gitconfig" persona.sshIdentityFile '~/.ssh/custom-key'
run_profile render-ssh work
grep -Fq 'IdentityFile /' "$profile_dir/ssh_config" && {
  echo 'expected the literal tilde form to be preserved' >&2
  exit 1
}
grep -Fq 'IdentityFile ~/.ssh/custom-key' "$profile_dir/ssh_config"

chflags nouchg "$profile_dir/gitconfig" 2>/dev/null || true
git config --file "$profile_dir/gitconfig" persona.sshIdentityFile \
  $'~/.ssh/custom-key\n  ProxyCommand false'
if run_profile render-ssh work >"$tmp_dir/ssh-injection.out" 2>&1; then
  echo 'expected a multiline SSH identity file to fail' >&2
  exit 1
fi
grep -Fq 'SSH identity file must be single-line' "$tmp_dir/ssh-injection.out"
git config --file "$profile_dir/gitconfig" persona.sshIdentityFile '~/.ssh/custom-key'

if FAKE_GH_USER=other-user run_profile verify work >"$tmp_dir/mismatch.out" 2>&1; then
  echo 'expected an authenticated identity mismatch to fail' >&2
  exit 1
fi
grep -Fq 'identity mismatch' "$tmp_dir/mismatch.out"

chflags nouchg "$profile_dir/gitconfig" 2>/dev/null || true
git config --file "$profile_dir/gitconfig" user.name 'Custom Name'
run_profile sync work
[ "$(git config --file "$profile_dir/gitconfig" --get user.name)" = 'Custom Name' ]
