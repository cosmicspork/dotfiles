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
.config/llama-server.env                       # server-wide flags
.config/llama-models.ini                       # per-model router presets
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
5. Populate the cache with at least one model, then enable both units:
   ```bash
   llama-server -hf <user>/<repo>:<quant>   # downloads into ~/.cache/llama.cpp, then Ctrl-C
   systemctl --user enable --now llama-update.timer llama-server.service
   ```
   The server runs in router mode and serves whatever is in `~/.cache/llama.cpp`,
   so adding a model is a download plus a restart — no env edit needed unless it
   wants non-default flags. Pre-fetch rather than letting the first start pull a
   cold model, or the download outruns the updater's health-check window.

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
- Router mode (`--models-preset`, passed from the unit because `%h` does not
  expand in an `EnvironmentFile`) means the server holds no weights at startup
  and loads a model on the first request naming it. Requests pick a model with
  the `model` field (POST) or `?model=` (GET); `GET /models` lists them.
- `--models-max 1` makes a second model evict the first instead of trying to
  hold both. Measured switch cost, Muse Glimmer to Qwen: 38 s including the
  eviction, the 49.6 GB load, and a short generation. A cold on-demand load of
  the 20 GB model is ~11 s. That latency is the deliberate trade for not
  parking a model in RAM.
- Preset section names must match the id the router derives, which is not always
  the tag you downloaded: `Qwen3-Coder-Next-UD-Q4_K_XL.gguf` resolves to
  `unsloth/Qwen3-Coder-Next-GGUF:Q4_K_XL`. Check `GET /models` after adding one;
  a name that matches nothing defines a second, unloadable model rather than
  erroring.
- `jinja = true` in `llama-models.ini` is required for OpenAI-style tool calling;
  without it the server returns 500 on any request carrying a `tools` param. It
  defaults to enabled as of b10362 but is set explicitly to survive a flip.
- `--sleep-idle-seconds` does return the memory: measured on this host, an idle
  child dropped usage from 31 GB to 11 GB and reported `sleeping`, and the next
  request woke it in ~8 s. That is the mechanism that keeps a model from sitting
  in RAM overnight; `--models-max 1` only bounds how many can be resident at once.
- `LLAMA_CACHE` is exported from `.zshrc.d/30-bazzite.zsh` as well as set in the
  unit, and the two must agree. Set only in the unit, an interactive
  `llama-server -hf` silently falls back to `~/.cache/huggingface/hub` and the
  router never sees the model — with no error, just a download that appears to
  have vanished.
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

## Workspace notes backup

Versions `~/src/README.md` and `~/src/docs/` — the cross-repo conventions file and the working
notes — without putting a `.git` inside `~/src`, which holds many nested repos and is expected
by tooling to read as *not* a git repository.

```
home/base/.local/bin/workspace-notes-sync
home/profiles/bazzite/.config/systemd/user/workspace-notes-sync.{service,timer}
home/profiles/macos/Library/.../switchboard/agents/dev.workspace-notes.sync.plist
```

A **bare** repo at `~/.workspace-notes.git` is paired with an explicit work tree, so git state
lives entirely outside `~/src`. Which paths are tracked is decided by a whitelist in
`$GIT_DIR/info/exclude`, not by the script, so the same helper works against any work tree:

```sh
git init --bare -b main ~/.workspace-notes.git
printf '*\n!README.md\n!docs/\n!docs/**\ndocs/archive/\n.DS_Store\n**/.DS_Store\ndocs/.*\n' \
  > ~/.workspace-notes.git/info/exclude
git --git-dir=$HOME/.workspace-notes.git --work-tree=$HOME/src add -A
git --git-dir=$HOME/.workspace-notes.git --work-tree=$HOME/src commit -m 'initial'
```

The leading `*` means nothing is tracked until it is explicitly un-ignored. **Check what the
first `add -A` actually staged before adding a remote** — a `docs/` directory can pick up
credential files dropped there by other tools.

Add a remote to get off-machine copies (`git ... remote add origin <url>`); with none
configured the helper commits locally and says so rather than failing.

Set `WORKSPACE_NOTES_GIT` / `WORKSPACE_NOTES_WORKTREE` to point it elsewhere.

On Bazzite: `systemctl --user enable --now workspace-notes-sync.timer`. On macOS the plist is
loaded from Switchboard's menu ("Workspace Notes Backup") rather than `~/Library/LaunchAgents`,
matching the other helpers there.
