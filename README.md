# dotfiles

Personal dotfiles for Debian-based devcontainers. Run once:

```bash
./bootstrap.sh
```

`home/` is rsynced into `$HOME`, then a batch of CLI tools and VS Code extensions are installed. Idempotent — safe to rerun.

## Scope and limitations

- **Linux + Debian/apt only.** Bails on macOS or any non-`apt-get` distro.
- **Debian 11 or 12+** assumed; older releases may lack packages used here.
- **amd64 and arm64 only.** Other architectures skip the GitHub-release installers.
- **Devcontainer-first.** Designed for Coder workspaces and local devcontainers.
- **Network required.** Pulls from apt, GitHub/GitLab release APIs, and a few `curl | bash` installers.
- **Changes login shell to zsh** for the invoking user.

## Layout

- `bootstrap.sh` — installer (devcontainer + Debian host essentials)
- `home/` — files rsynced into `$HOME`
- `manifests/vscode-extensions.txt` — VS Code extensions installed by `bootstrap.sh`
- `manifests/composer-globals.txt` — top-level Composer global requires
- `Brewfile` — host-only extras (Homebrew formulas/casks/taps, Flatpaks, VS Code extensions, uv tools). Not used by `bootstrap.sh`; apply on personal machines with brew installed.

## Host setup (personal machines)

```bash
brew bundle install --file=Brewfile          # brew + flatpak + vscode + uv tools
composer global require $(grep -v '^#' < manifests/composer-globals.txt | xargs)
```

The Brewfile is a snapshot — regenerate with `brew bundle dump --file=Brewfile --force --describe` after deliberate additions, and `brew bundle check --file=Brewfile` to see drift.

### GnuPG

`~/.gnupg/common.conf`:
```
use-keyboxd
```

`~/.gnupg/gpg-agent.conf`:
```
pinentry-program /usr/bin/pinentry-qt
default-cache-ttl 34560000
max-cache-ttl 34560000
allow-preset-passphrase
```

`~/.config/systemd/user/gpg-preset.service` preloads the signing key's passphrase from KWallet into gpg-agent's cache at session start, so Git operations never prompt for it. It pairs with `allow-preset-passphrase` and the long cache TTL above. Per-machine setup (one-time):

1. Store the passphrase in KWallet keyed by keygrip:
   ```bash
   secret-tool store --label="GPG <fingerprint>" gpg-keygrip <KEYGRIP>
   ```
   Find the keygrip with `gpg --list-secret-keys --with-keygrip`.
2. Set `KEYGRIP=` in the service to the signing subkey's keygrip, then enable it:
   ```bash
   systemctl --user enable --now gpg-preset.service
   ```

```ini
[Unit]
Description=Preload GPG signing key passphrase from KWallet
Requires=graphical-session.target
After=graphical-session.target gpg-agent.socket
Wants=gpg-agent.socket

[Service]
Type=oneshot
Environment=KEYGRIP=<KEYGRIP>
ExecStart=/bin/sh -c '/usr/bin/secret-tool lookup gpg-keygrip ${KEYGRIP} | /usr/libexec/gpg-preset-passphrase --preset ${KEYGRIP}'
RemainAfterExit=true

[Install]
WantedBy=graphical-session.target
```
