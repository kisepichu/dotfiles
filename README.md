# dotfiles

Public chezmoi source for Windows, WSL Ubuntu, macOS, and NixOS dotfiles and agent workflows.

## Fresh NixOS

NixOS provides `git`, `curl`, and `mise` as system packages and enables `programs.nix-ld` so mise's prebuilt Node binary can run. Clone this repository over HTTPS, then run the NixOS-only bootstrap from the checkout:

```bash
mkdir -p ~/repos
git clone https://github.com/kisepichu/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles
./scripts/bootstrap-nixos.sh
```

The bootstrap applies this chezmoi source non-interactively, which installs the declared mise tools (including Codex) and the omp and Claude Code CLIs under `~/.local/bin`. Re-running it restores chezmoi-managed files to the repository state, so commit intentional local edits first. It does not perform any login or create credentials.

Create a dedicated GitHub key on the NixOS machine after the bootstrap:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_glaceon
cat ~/.ssh/id_ed25519_github_glaceon.pub
```

Register only the displayed public key in GitHub, then add this host entry to `~/.ssh/config`:

```sshconfig
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_glaceon
  IdentitiesOnly yes
```

```bash
chmod 600 ~/.ssh/config
ssh -T git@github.com
```

Complete the agent authentication manually on that machine:

```bash
codex login
claude login
# omp: start `omp`, then run /login
```

## Fresh macOS

This path is for a Windows/WSL-first workflow on a new Mac. It is separate from the WSL bootstrap.

```bash
xcode-select --install
mkdir -p ~/repos
git clone https://github.com/kisepichu/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles
./scripts/bootstrap-macos.sh
```

After the script completes, open Karabiner-Elements once and grant the permissions requested by macOS.

Detailed notes: `docs/macos-initial-setup.md`

## Fresh WSL Ubuntu

1. Install WSL and Ubuntu from Windows.

   ```powershell
   wsl --install -d Ubuntu
   ```

2. Update WSL, then open the Ubuntu shell.

   ```powershell
   wsl --update
   ```

3. Clone this repository in WSL.

   ```bash
   sudo apt-get update
   sudo apt-get install -y git
   mkdir -p ~/repos
   git clone https://github.com/kisepichu/dotfiles.git ~/repos/dotfiles
   cd ~/repos/dotfiles
   ```

4. Run the WSL bootstrap.

   ```bash
   ./scripts/bootstrap-wsl-ubuntu.sh
   ```

5. Restart the shell after the bootstrap changes the default shell to fish.

   ```bash
   exec fish -l
   ```

## Docker Engine On WSL

Install Docker Engine directly inside WSL Ubuntu when container-based project work is needed.

Docker Engine expects systemd in WSL. Current Ubuntu installs through `wsl --install` should use systemd by default; verify it when needed:

```bash
cat /proc/1/comm
```

If the output is not `systemd`, enable it inside the distro and restart WSL:

```bash
sudoedit /etc/wsl.conf
```

Add or update this section while preserving any existing settings:

```ini
[boot]
systemd=true
```

```powershell
wsl --terminate Ubuntu
```

Replace `Ubuntu` with the distro name when it differs.

```bash
cd ~/repos/dotfiles
./scripts/install-docker-engine-wsl.sh
```

The script prompts before adding your user to the `docker` group. Accept only if you want to run Docker without `sudo`; Docker daemon access is effectively root-equivalent inside the WSL distro.

Then close and reopen the WSL session if you accepted the group change. Verify the install:

```bash
docker run --rm hello-world
docker compose version
```

If you declined the group change, use `sudo` for daemon access:

```bash
sudo docker run --rm hello-world
docker compose version
```

The script follows Docker's official Ubuntu apt repository flow and installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`.

## Nix (optional)

Nix is not part of the core bootstrap. Install it explicitly when a reproducible `nix develop` shell or optional Nix-managed tooling is wanted. The script uses the Determinate Nix Installer and supports macOS and WSL Ubuntu.

```bash
cd ~/repos/dotfiles
./scripts/install-nix.sh
```

On WSL, the script detects whether systemd is PID 1. If it is not (no `systemd=true` in `/etc/wsl.conf`), it installs with `--init none` so the install does not depend on a systemd-managed `nix-daemon`. For a systemd-managed daemon, enable systemd in WSL first (see the Docker section above).

Options:

- `NIX_INSTALL_NO_CONFIRM=1` runs the installer non-interactively.
- `NIX_INSTALL_DETERMINATE=1` installs Determinate Nix instead of upstream Nix.

Open a new shell after installing; `conf.d/nix.fish` sources the nix profile automatically. To uninstall a Determinate install:

```bash
/nix/nix-installer uninstall
```

## Rust

Rust is managed by `mise` (declared in `~/.config/mise/config.toml`). After `chezmoi apply`, `mise install` installs the toolchain and `run_onchange_after_45-rust-components.sh.tmpl` adds the `rust-analyzer` and `rust-src` components that neovim (rustaceanvim) needs. No manual step is required; open neovim in a Rust project and the LSP starts.

## Agent CLIs

`codex`, `claude`, and `omp` are installed on every platform (macOS, WSL Ubuntu, NixOS) by `chezmoi apply`:

- `codex` is declared in the `mise` tool list (`~/.config/mise/config.toml`) and resolves to the `aqua:openai/codex` prebuilt release binary. Upgrade it with `mise up codex`.
- `omp` and `claude` are installed by `run_once_after_50-install-agent-clis.sh` from their upstream installers (`https://omp.sh/install`, `https://claude.ai/install.sh`) into `~/.local/bin`.

That script is first-install only: it skips any CLI already on `PATH`, because both binaries update themselves (`omp update`, Claude Code's built-in updater). Their versions are deliberately not pinned here. A failed download warns instead of aborting `chezmoi apply`.

Machines set up before this layout may hold a second copy from another channel: remove the Homebrew cask on macOS (`brew uninstall --cask codex`) and the npm globals installed by the old NixOS bootstrap (`npm --prefix ~/.local uninstall -g @openai/codex @anthropic-ai/claude-code`), so each CLI has exactly one install.

Authenticate once per machine; this repository stores no credentials.

```bash
codex login
claude login
# omp: start `omp`, then run /login
```

## Validation

Before committing, run:

```bash
prek run --all-files
```

If `prek` is not available, run:

```bash
pre-commit run --all-files
```
