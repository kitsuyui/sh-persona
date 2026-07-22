#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
profile_root="$tmp_dir/profiles"

make_profile() {
  local user=$2 email=$3 profile_dir="$profile_root/$1"
  mkdir -p "$profile_dir"
  git config --file "$profile_dir/gitconfig" github.user "$user"
  git config --file "$profile_dir/gitconfig" user.name "$user"
  git config --file "$profile_dir/gitconfig" user.email "$email"
  git config --file "$profile_dir/gitconfig" user.signingkey "$user"
  git config --file "$profile_dir/gitconfig" gpg.format openpgp
  git config --file "$profile_dir/gitconfig" gpg.program gpg
  git config --file "$profile_dir/gitconfig" persona.signing true
  git config --file "$profile_dir/gitconfig" persona.sshAlias "$user.github.com.invalid"
  git config --file "$profile_dir/gitconfig" persona.privateOnly true
  printf 'Host %s.github.com.invalid\n  HostName github.com\n  User git\n' "$user" \
    >"$profile_dir/ssh_config"
}

make_profile work example-user example-user@example.com
make_profile team example-bot example-bot@example.com
make_profile test example-test example-test@example.com

export GH_PERSONA_PROFILE_ROOT="$profile_root"
export GH_PERSONA_REAL_GH=/definitely/unavailable/gh

new_repo() {
  local path=$1
  mkdir -p "$path"
  git -C "$path" init -q
}

assert_config() {
  local repo=$1 key=$2 expected=$3 actual
  actual=$(git -C "$repo" config --local --get-all "$key")
  [ "$actual" = "$expected" ] || {
    printf 'unexpected %s: %s\n' "$key" "$actual" >&2
    exit 1
  }
}

assert_config_absent() {
  local repo=$1 key=$2
  if git -C "$repo" config --local --get-all "$key" >/dev/null; then
    printf 'expected %s to be absent\n' "$key" >&2
    exit 1
  fi
}

personas=(work team test)
users=(example-user example-bot example-test)
profiles=(work team test)
aliases=(
  'ssh://example-user.github.com.invalid/'
  'ssh://example-bot.github.com.invalid/'
  'ssh://example-test.github.com.invalid/'
)
old_aliases=(
  'ssh://example-user.github.com/'
  'ssh://example-bot.github.com/'
  'ssh://example-test.github.com/'
)

for index in "${!personas[@]}"; do
  persona=${personas[$index]}
  repo="$tmp_dir/$persona"
  new_repo "$repo"
  (
    cd "$repo"
    "$PROJECT_ROOT/git-persona" apply "$persona"
    "$PROJECT_ROOT/git-persona" verify "$persona"
  )
  assert_config "$repo" user.name "${users[$index]}"
  assert_config "$repo" gh.profile "${profiles[$index]}"
  assert_config "$repo" gh.user "${users[$index]}"
  assert_config "$repo" persona.profile "${profiles[$index]}"
  assert_config "$repo" persona.githubUser "${users[$index]}"
  assert_config_absent "$repo" persona.privateOnly
  assert_config_absent "$repo" gh.private-only
  assert_config "$repo" "url.${aliases[$index]}.insteadOf" 'git@github.com:'
  status=$(cd "$repo" && "$PROJECT_ROOT/git-persona" status)
  grep -Fq "persona=$persona" <<<"$status"
  grep -Fq 'verified=true' <<<"$status"
done

switch_repo="$tmp_dir/switch"
new_repo "$switch_repo"
(
  cd "$switch_repo"
  for index in "${!personas[@]}"; do
    persona=${personas[$index]}
    "$PROJECT_ROOT/git-persona" apply "$persona"
    git config --local --add \
      "url.${old_aliases[$index]}.insteadOf" 'git@github.com:'
  done
  "$PROJECT_ROOT/git-persona" apply work
  "$PROJECT_ROOT/git-persona" verify work
)

verify_repo="$tmp_dir/verify"
new_repo "$verify_repo"
(cd "$verify_repo" && "$PROJECT_ROOT/git-persona" apply team)
git -C "$verify_repo" config --local user.email wrong@example.com
if (cd "$verify_repo" && "$PROJECT_ROOT/git-persona" verify team) \
  >"$tmp_dir/verify-failure.out" 2>&1; then
  echo 'expected verify to detect a mismatched config' >&2
  exit 1
fi
grep -Fq 'local config mismatch: user.email' "$tmp_dir/verify-failure.out"

ssh_sign_repo="$tmp_dir/ssh-sign"
new_repo "$ssh_sign_repo"
git config --file "$profile_root/test/gitconfig" gpg.format ssh
git config --file "$profile_root/test/gitconfig" gpg.ssh.program custom-ssh-keygen
(cd "$ssh_sign_repo" && "$PROJECT_ROOT/git-persona" apply test)
assert_config "$ssh_sign_repo" gpg.ssh.program custom-ssh-keygen
if git -C "$ssh_sign_repo" config --local --get gpg.program >/dev/null; then
  echo 'expected the OpenPGP program to be absent for SSH signing' >&2
  exit 1
fi
git config --file "$profile_root/test/gitconfig" gpg.format openpgp
git config --file "$profile_root/test/gitconfig" --unset gpg.ssh.program

unsigned_repo="$tmp_dir/unsigned"
new_repo "$unsigned_repo"
git config --file "$profile_root/test/gitconfig" persona.signing false
(cd "$unsigned_repo" && "$PROJECT_ROOT/git-persona" apply test)
if git -C "$unsigned_repo" config --local --get user.signingkey >/dev/null; then
  echo 'expected signing config to be absent when disabled' >&2
  exit 1
fi
git config --file "$profile_root/test/gitconfig" persona.signing true

subcommand_repo="$tmp_dir/subcommand"
new_repo "$subcommand_repo"
(
  cd "$subcommand_repo"
  PATH="$PROJECT_ROOT:$PATH" git persona apply test
  PATH="$PROJECT_ROOT:$PATH" git persona verify test
)

if "$PROJECT_ROOT/git-persona" apply unknown \
  >"$tmp_dir/unknown.out" 2>&1; then
  echo 'expected an unknown persona to fail' >&2
  exit 1
fi
grep -Fq 'unknown persona' "$tmp_dir/unknown.out"

if (cd "$tmp_dir" && "$PROJECT_ROOT/git-persona" apply work) \
  >"$tmp_dir/not-repo.out" 2>&1; then
  echo 'expected use outside a repository to fail' >&2
  exit 1
fi
grep -Fq 'not inside a Git repository' "$tmp_dir/not-repo.out"

[ "$("$PROJECT_ROOT/git-persona" list | tr '\n' ' ')" = 'team test work ' ]
