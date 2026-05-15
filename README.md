# chezmoi-dotfiles

Public chezmoi source for Windows + WSL Ubuntu dotfiles and agent workflows.

## Fresh WSL Ubuntu

1. Install or update WSL from Windows.

   ```powershell
   wsl --install
   wsl --update
   ```

2. Install Ubuntu from WSL, then open the Ubuntu shell.

   ```powershell
   wsl --install -d Ubuntu
   ```

3. Clone this repository in WSL.

   ```bash
   sudo apt-get update
   sudo apt-get install -y git
   mkdir -p ~/repos
   git clone https://github.com/kisepichu/chezmoi-dotfiles.git ~/repos/chezmoi-dotfiles
   cd ~/repos/chezmoi-dotfiles
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
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
```

```powershell
wsl --terminate Ubuntu
```

Replace `Ubuntu` with the distro name when it differs.

```bash
cd ~/repos/chezmoi-dotfiles
./scripts/install-docker-engine-wsl.sh
```

Then close and reopen the WSL session so the `docker` group membership is refreshed. Verify the install:

```bash
docker run hello-world
docker compose version
```

The script follows Docker's official Ubuntu apt repository flow and installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`.

## Validation

Before committing, run:

```bash
prek run --all-files
```

If `prek` is not available, run:

```bash
pre-commit run --all-files
```
