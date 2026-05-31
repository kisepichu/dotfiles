# dotfiles

Public chezmoi source for Windows + WSL Ubuntu dotfiles and agent workflows.

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

## Validation

Before committing, run:

```bash
prek run --all-files
```

If `prek` is not available, run:

```bash
pre-commit run --all-files
```
