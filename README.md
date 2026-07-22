# sh-persona

`sh-persona` keeps Git commit identity, SSH routing, and GitHub CLI credentials
aligned with a repository-selected profile.

It is designed for people who use multiple GitHub accounts and want identity
selection to be explicit, repository-local, and fail-closed.

## Commands

- `git-persona`: applies and verifies repository-local Git, SSH, and signing
  settings without accessing the network.
- `gh-persona`: runs GitHub CLI with the credential profile selected by the
  current repository and rejects unsafe credential or identity mutations.
- `persona-profile`: provisions and verifies the non-secret Git and SSH files
  associated with a GitHub CLI profile.
- `gh-persona-admin`: performs explicit authentication and profile mutation.
- `persona`: provides a convenience facade over the independent primitives.

## Requirements

- Bash
- Git
- OpenSSH
- [GitHub CLI](https://cli.github.com/)

Immutable-file hardening uses `chflags` when it is available. The remaining
profile isolation and verification features are portable across Unix-like
systems.

## Installation

Clone the repository and put its root on `PATH`:

```sh
git clone https://github.com/kitsuyui/sh-persona.git ~/.local/share/sh-persona
export PATH="$HOME/.local/share/sh-persona:$PATH"
```

To guard the ordinary `gh` command as well, put `gh-guard-bin` before the
directory containing the real GitHub CLI:

```sh
export PATH="$HOME/.local/share/sh-persona/gh-guard-bin:$PATH"
```

The guard locates the real GitHub CLI later on `PATH`. Set
`GH_PERSONA_REAL_GH` to an absolute executable path when automatic discovery is
not suitable.

## Profile layout

Profiles live under `${GH_PERSONA_PROFILE_ROOT:-~/.config/gh-profiles}`:

```text
~/.config/gh-profiles/work/
├── config.yml    # owned by gh
├── hosts.yml     # owned by gh; contains credential references
├── gitconfig     # Git identity, signing, and SSH defaults
└── ssh_config    # isolated SSH host alias
```

`config.yml` and `hosts.yml` remain GitHub CLI files. `gitconfig` and
`ssh_config` are non-secret profile configuration owned by `sh-persona`.

Authenticate and initialize a profile:

```sh
gh-persona-admin login work example-user
persona profile sync work
```

Login uses `--skip-ssh-key`; it does not create or upload SSH keys.

The generated defaults use:

- the GitHub login as the Git author name;
- the account's public email or GitHub noreply address;
- `~/.ssh/<login>` as the SSH identity file;
- `<login>.github.com.invalid` as a profile-local SSH alias;
- signing disabled until explicitly configured.

Unlock `gitconfig` to override those defaults, then regenerate and relock the
SSH configuration:

```sh
persona profile unlock work
git config --file ~/.config/gh-profiles/work/gitconfig \
  persona.sshIdentityFile ~/.ssh/custom-key
persona profile render-ssh work
persona profile lock work
```

Repository authorization is delegated to GitHub. The selected profile chooses
the account and token, while that token's repository access and permission
scopes determine which operations GitHub accepts. `sh-persona` does not encode
repository visibility, ownership, or local permission tiers.

## Repository selection

Select and verify a profile inside a repository:

```sh
persona apply work
persona verify
persona status
persona gh pr list
```

The selected profile is recorded in repository-local Git config. Applying a
profile aligns all of the following values:

- `user.name` and `user.email`;
- optional signing configuration;
- `core.sshCommand`;
- the `git@github.com:` URL rewrite;
- expected GitHub login.

The direct primitives remain independently usable:

```sh
git-persona apply work
git-persona verify work
gh-persona pr list
```

Because `git-persona` follows Git's external-subcommand convention,
`git persona ...` is also available when the repository root is on `PATH`.

## Safety model

`gh-persona` clears ambient token and repository environment variables, sets
`GH_CONFIG_DIR` to the selected profile, verifies the authenticated GitHub
login, and then evaluates the requested command.

Authentication mutation, token output, configuration mutation, extension
installation, and explicit host overrides are rejected. Repository operations
otherwise pass through to GitHub, which remains the source of truth for
authorization. The legacy `persona.privateOnly` and `gh.private-only`
settings are ignored; `git-persona apply` removes their repository-local
copies.

Credential mutation is deliberately separated into `gh-persona-admin`. The
default `~/.config/gh` directory can be replaced by an immutable sentinel:

```sh
gh-persona-admin seal-default
```

The command first moves the previous directory to a timestamped, recoverable
backup under the profile root.

## Development

Run all checks with:

```sh
tests/check.sh
```

The behavior tests use temporary profiles and a fake GitHub CLI. They do not
access real accounts or repositories.

## License

[MIT](LICENSE)
