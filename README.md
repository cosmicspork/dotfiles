# dotfiles

Profiled personal dotfiles. `devcontainer` is the default/base development target, with host overlays for macOS and Bazzite.

Run once:

```bash
./install
```

Override detection when needed:

```bash
./install --profile devcontainer
./install --profile macos
./install --profile bazzite
./install --home-only --profile macos
```

## Profiles

- `devcontainer` — Debian/apt bootstrap plus devcontainer-focused home overlay. This remains the fallback/default profile.
- `macos` — base home overlay plus macOS shell additions, the shared `manifests/Brewfile`, and macOS casks in `manifests/macos/Brewfile`.
- `bazzite` — base home overlay plus Bazzite shell additions. Installs the shared `manifests/Brewfile` via Homebrew (preinstalled on Bazzite); the Flatpak, uv-tool, and font manifests are present but not yet wired.

Profile detection:

1. `--profile <name>` argument
2. `DOTFILES_PROFILE=<name>` environment variable
3. macOS (`Darwin`) => `macos`
4. Bazzite `/etc/os-release` => `bazzite`
5. fallback => `devcontainer`

## Layout

```text
install                         # entrypoint; delegates to bootstrap.sh
bootstrap.sh                    # profile-aware installer
home/base/                      # applied for every profile
home/base/.zshrc.d/             # ordered shell fragments
home/profiles/devcontainer/     # devcontainer overlay
home/profiles/macos/            # macOS overlay
home/profiles/bazzite/          # Bazzite overlay
manifests/vscode-extensions.txt        # shared VS Code extensions (all profiles)
manifests/composer-globals.txt         # Composer global package list (shared)
manifests/Brewfile                     # shared Homebrew formulae (macOS + Bazzite)
manifests/devcontainer/tools.txt       # devcontainer apt tool list
manifests/macos/Brewfile               # macOS-only Homebrew casks
manifests/bazzite/flatpaks.txt         # Bazzite Flatpak application IDs
manifests/bazzite/fonts.txt            # Bazzite Nerd Fonts (shared with macOS cask)
manifests/bazzite/packages.txt         # Bazzite native packages (placeholder)
manifests/bazzite/uv-tools.txt         # Bazzite uv tools
```

Home files are applied by copying `home/base/` first, then `home/profiles/<profile>/` over it.

## Devcontainer setup

`./install` installs Debian tooling, GitHub/GitLab CLIs, shell tools, npm global tools, and VS Code extensions (from the shared `manifests/vscode-extensions.txt`), then applies the base + devcontainer home overlays.

Scope and limitations:

- Debian/apt package bootstrap only for the `devcontainer` profile.
- Debian 11 or 12+ assumed for package names.
- amd64 and arm64 only for direct GitHub-release binary installers.
- Network required for package managers and release downloads.
- Changes login shell to zsh when possible.

## macOS setup

```bash
./install --profile macos
```

This applies base + macOS home overlays, installs the shared VS Code extensions via the `code` CLI, and runs both Homebrew bundles:

```bash
brew bundle install --file manifests/Brewfile
brew bundle install --file manifests/macos/Brewfile
```

To apply only home files without package changes:

```bash
./install --profile macos --home-only
```

## Composer globals

```bash
composer global require $(grep -v '^#' < manifests/composer-globals.txt | xargs)
```

## GnuPG on Bazzite/Linux desktops

`~/.gnupg/common.conf`:

```text
use-keyboxd
```

`~/.gnupg/gpg-agent.conf`:

```text
pinentry-program /usr/bin/pinentry-qt
default-cache-ttl 34560000
max-cache-ttl 34560000
allow-preset-passphrase
```

`~/.config/systemd/user/gpg-preset.service` preloads the signing key's passphrase from KWallet into gpg-agent's cache at session start, so Git operations never prompt for it. It pairs with `allow-preset-passphrase` and the long cache TTL above. Per-machine setup:

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
