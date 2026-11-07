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
- `bazzite` — base home overlay plus Bazzite shell additions. Installs the shared `manifests/Brewfile` and the Linux-only `manifests/bazzite/Brewfile` via Homebrew (preinstalled on Bazzite); the Flatpak, uv-tool, and font manifests are present but not yet wired.

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
manifests/bazzite/Brewfile             # Bazzite-only Homebrew formulae (WebKitGTK headers, metrics stack)
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

## Rust on the host

`rustup` comes from the shared Brewfile and is keg-only, so the macOS and Bazzite
shell fragments put its keg bin (`$(brew --prefix)/opt/rustup/bin`) on `PATH`;
that is where `cargo` and `rustc` live. A repo's `rust-toolchain.toml` picks the
toolchain, which rustup installs on first use. Alongside it:

- `cargo-nextest`, the test runner the Rust repos' CI uses.
- `cargo-zigbuild` (and `zig`, its dependency) for static musl builds. Fedora's
  `musl-gcc` is not installable on an immutable image, and `cargo zigbuild
  --target x86_64-unknown-linux-musl` needs nothing else. Add the target first
  with `rustup target add x86_64-unknown-linux-musl`.
- On Bazzite, `manifests/bazzite/Brewfile` adds the WebKitGTK, GTK3 and appindicator
  headers a Tauri app compiles against. They stay off the default pkg-config path
  on purpose, so brew's libraries never win over the image's for other builds; a
  build that needs them prefixes `PKG_CONFIG_PATH="$(brew --prefix)/lib/pkgconfig:$(brew --prefix)/share/pkgconfig"`
  (tracon's `just wrapper` and `just wrapper-check` do this themselves). The
  binary still loads the image's own WebKitGTK at runtime.

Bundling a Tauri AppImage still wants a Fedora container (`distrobox`), since the
bundler collects system libraries; checks, tests and release builds do not.

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

## Local metrics on Bazzite (VictoriaMetrics)

Keeps 90 days of what the laptop was doing, so "the fan just spun up, what was
it?" has an answer after the fact. The journal already keeps history; CPU,
temperature, fan and power had none, only their current values.

Tracked files (bazzite profile):

```text
.config/systemd/user/victoria-metrics.service   # the store, and the one unit to switch
.config/systemd/user/node-exporter.service      # sensors, power, pressure; runs with it
.config/systemd/user/cgroup-metrics.service     # per-app cgroup counters; runs with it
.config/victoria-metrics/scrape.yaml
.config/victoria-metrics/dashboards/laptop.json # vmui: Dashboards
.config/switchboard/helpers.toml                # tray entries, including "Metrics"
.local/bin/cgroup-metrics
.local/bin/what-happened
tests/test-cgroup-metrics.sh                    # repo-level; run manually
```

`victoriametrics` and `node_exporter` come from `manifests/bazzite/Brewfile`. Data
lives in `~/.local/state/victoria-metrics` and is not tracked.

Per-machine setup:

1. Generate the admin key. It is host-only and never tracked; the unit refuses to
   start without it rather than leave delete, snapshot and pprof open.
   ```bash
   umask 077 && openssl rand -hex 32 > ~/.config/victoria-metrics/admin-key
   ```
2. Start it and keep it on at login, from Switchboard (Metrics: Start at login,
   after Reload config) or:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now victoria-metrics.service
   ```
3. The query UI is `http://127.0.0.1:8428/vmui/` (Switchboard: Open in browser);
   the laptop dashboard is under Dashboards.

Asking what happened:

```bash
what-happened                          # the last 15 minutes
what-happened --since 2h
what-happened --since 17:40 --until 17:50
```

It prints peak temperature, fan, package power and busy CPU, a per-minute
timeline with the top app by CPU in each minute, the top apps over the window,
then journal warnings and unit start/stop lines from the same window. The
journal half works with the metrics stack off.

What is recorded, every 15 s:

- **Per app**, from cgroups: CPU time, memory, swap, disk read and write, task
  count. A systemd session already runs each app in its own cgroup (a Flatpak in
  `app-flatpak-<id>-<n>.scope`, an autostart entry in `app-<id>@autostart.service`,
  each system service in `system.slice`), so nothing walks processes. Series
  carry `app`, a stable name with the launch counter stripped
  (`com.rtosta.zapzap`, `steam`, `fw-fanctrl`), and `unit`, the raw cgroup.
- **The machine**, from node_exporter: CPU and GPU temperature, fan RPM and
  package power (hwmon), GPU busy (drm), CPU time and clock, pressure (PSI),
  memory, disk, network, battery and AC.

Starting points (MetricsQL):

```
# CPU by app, in cores
sum by (app) (rate(cgroup_cpu_usage_seconds_total[1m]))
# CPU temperature; sensors are picked by chip name, since `chip` is a bus address
node_hwmon_temp_celsius * on(chip) group_left(chip_name) node_hwmon_chip_names{chip_name="k10temp"}
# Fan
max(node_hwmon_fan_rpm)
```

Notes:

- Query by `app` and sum (`sum by (app)`). The script keeps one series per
  cgroup on purpose: summing there would make a counter drop whenever one
  instance of an app exits, which `rate()` reads as a reset and turns into a
  false spike.
- The granularity is the cgroup, not the process. Everything started from a
  Konsole window (an agent, a build) counts as `org.kde.konsole`; drill into
  processes live with `top` while it is happening.
- It listens on `127.0.0.1` only, with CORS off: by default VictoriaMetrics
  answers any `Origin` with `*`, which would let any web page read which apps you
  run. The admin endpoints need `?authKey=` with the key above. Reads stay open
  to local processes, which can read the same from `/proc` anyway.
- Pruning is VictoriaMetrics' own: `-retentionPeriod=90d` drops older data, and
  `-storage.minFreeDiskSpaceBytes=10GB` stops writes before the disk fills.
- `-search.latencyOffset=5s` instead of the default 30s, so a query right after
  a spike sees it.
- `StateDirectory=` is deliberately not used. With `~/.config/victoria-metrics`
  present, systemd takes it for the pre-v254 state location and symlinks
  `~/.local/state/victoria-metrics` to it, which puts the data in `.config`.
- node_exporter runs with `--collector.disable-defaults` and an explicit list.
  `rapl` is left out because its energy counters are root-only.
- cgroup-metrics is a loop rather than a 15-second timer: a timer logs a start
  and a finish on every run, about 11k journal lines a day.
- All three units have `CPUWeight=20` and memory caps; telemetry should never
  be what spins the fan. Measured here over its first 5 minutes, including
  startup and test queries: 0.86% of one core in total and about 110 MB of
  memory, ingesting about 110 samples/s (roughly 1,600 series). VictoriaMetrics
  usually stores under a byte per sample once merged, which puts 90 days near
  1 GB; that figure is an estimate, not a measurement.
- Run the tests after changing cgroup-metrics:
  ```bash
  ./tests/test-cgroup-metrics.sh
  ```
