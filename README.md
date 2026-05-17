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

- `bootstrap.sh` — installer
- `home/` — files rsynced into `$HOME`
- `manifests/vscode-extensions.txt` — VS Code extensions
