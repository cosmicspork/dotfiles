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
tests/                                 # repo-level tests; not copied into $HOME
```

Home files are applied by copying `home/base/` first, then `home/profiles/<profile>/` over it.

## Devcontainer setup

`./install` installs Debian tooling, GitHub/GitLab CLIs, shell tools, npm global tools, Composer globals (from the shared `manifests/composer-globals.txt`), and VS Code extensions (from the shared `manifests/vscode-extensions.txt`), then applies the base + devcontainer home overlays.

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

This applies base + macOS home overlays, installs the shared VS Code extensions via the `code` CLI and the shared Composer globals, and runs both Homebrew bundles:

```bash
brew bundle install --file manifests/Brewfile
brew bundle install --file manifests/macos/Brewfile
```

To apply only home files without package changes:

```bash
./install --profile macos --home-only
```

## Composer globals

`manifests/composer-globals.txt` is installed on every profile: bootstrap requires
any package on the list that `composer global show` does not already report, so
re-running `./install` never re-resolves what is present. Skipped with a warning
when `composer` is not on `PATH` (devcontainer images without PHP). `~/.config/composer/vendor/bin`
is already on `PATH` via the base shell overlay.

A bare entry is required as `*`, so nothing is pinned to the major it happened to
be installed at and `composer global update` can cross majors freely. These are
personal CLI tools where being current beats being stable; append a constraint
(`vendor/pkg:^2`) to an entry to deliberately hold one back.

Note that bootstrap only installs what is *missing* — it never updates. Moving
existing globals forward is a separate, explicit step:

```bash
composer global update
```

To install by hand:

```bash
composer global require $(sed 's/#.*//;/^[[:space:]]*$/d;/:/!s/$/:*/' manifests/composer-globals.txt | xargs)
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

## Local LLM inference on Bazzite (llama.cpp + Vulkan)

Runs `llama-server` against the Radeon 890M iGPU via Vulkan/RADV, exposing an
OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1`. ROCm is deliberately
not used: it cannot allocate from GTT on gfx1150, so large models OOM after the
first request.

Tracked files (bazzite profile):

```text
.local/bin/update-llama-cpp                    # source build + atomic release switch
.config/systemd/user/llama-update.{service,timer}
.config/systemd/user/llama-server.service
.config/llama-server.env                       # model and flags
tests/test-update.sh                           # repo-level; run manually
```

Build output lives in `~/.local/opt/llama.cpp/{releases,current}` and is not
tracked — it is several hundred MB per release. The updater keeps the active
release plus one approved fallback.

Per-machine setup:

1. Raise the GTT pool so the iGPU can address more than the kernel default of
   half of RAM. Reboot required.
   ```bash
   sudo rpm-ostree kargs \
     --append-if-missing=amdgpu.gttsize=65536 \
     --append-if-missing=ttm.pages_limit=16777216
   ```
   `65536` MB = 64 GiB; `16777216` pages x 4 KiB = the same 64 GiB.
   `ttm.pages_limit` is the binding constraint — setting only `gttsize` does
   nothing. Size it to leave the OS comfortable headroom.
2. Symlink the binaries onto `PATH`. They point at `current/`, so they follow
   the atomic release switch without needing to be recreated.
   ```bash
   for b in llama-server llama-cli llama-bench; do
     ln -sfn "$HOME/.local/opt/llama.cpp/current/build/bin/$b" "$HOME/.local/bin/$b"
   done
   ```
3. Build the first release. Takes several minutes; needs AC power.
   ```bash
   systemctl --user start llama-update.service
   journalctl --user -u llama-update.service -f
   ```
4. Generate the API key. It is host-only and never tracked; the unit refuses to
   start without it rather than quietly serving unauthenticated.
   ```bash
   umask 077 && openssl rand -hex 32 > ~/.config/llama-server.key
   ```
5. Pick a model in `~/.config/llama-server.env`, then enable both units:
   ```bash
   systemctl --user enable --now llama-update.timer llama-server.service
   ```
   First start downloads the model into `~/.cache/llama.cpp`, which can take a
   while on a cold cache. Pre-fetch it before enabling the service if the
   download would outrun the updater's health-check window.

Notes:

- `llama-server` binds to `127.0.0.1`. Do not move it to `0.0.0.0` on a portable
  machine.
- `--cors-origins localhost` is not redundant with that bind. CORS defaults to
  `*` with credentials enabled, which echoes back any `Origin`, so any page you
  browse could drive the server from your own machine. It costs nothing here:
  local process clients send no `Origin` and are not subject to CORS.
- The API key is what actually protects the endpoint. CORS does not stop DNS
  rebinding — the server performs no `Host` header validation — and it does not
  stop other local processes. Any client, including omp, needs the key.
- `--jinja` in `llama-server.env` is required for OpenAI-style tool calling;
  without it the server returns 500 on any request carrying a `tools` param.
- The update timer fires daily but `LLAMA_MIN_INTERVAL=604800` in the service
  holds rebuilds to weekly. The daily cadence exists because
  `ConditionACPower=true` marks a battery-time run as handled, so `Persistent=`
  would not replay a weekly schedule — the skip would silently cost a week.
- The updater validates a candidate by building it, confirming it enumerates a
  Vulkan device, then restarting `llama-server.service` and waiting on
  `/health`. It only marks a release `.approved` after that passes, and rolls
  back to the previous approved release otherwise. Without
  `llama-server.service` installed, that server-side validation is skipped.
- Run the tests after changing the updater:
  ```bash
  ./tests/test-update.sh
  ```
  They default to the tracked source. Override with
  `SCRIPT=~/.local/bin/update-llama-cpp` to test an installed copy.
