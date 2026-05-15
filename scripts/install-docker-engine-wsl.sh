#!/usr/bin/env bash
set -euo pipefail

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "warning: this script is intended for Ubuntu on WSL" >&2
fi

if [ ! -r /etc/os-release ]; then
  echo "error: /etc/os-release is missing" >&2
  exit 1
fi

. /etc/os-release

if [ "${ID:-}" != "ubuntu" ]; then
  echo "error: this script supports Ubuntu only; detected: ${ID:-unknown}" >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "error: sudo is required" >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "error: systemctl is required; enable systemd in WSL first" >&2
  exit 1
fi

if [ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]; then
  echo "error: systemd is not PID 1; enable systemd in WSL and restart WSL first" >&2
  exit 1
fi

if ! systemctl is-system-running >/dev/null 2>&1; then
  echo "warning: systemd does not appear fully running; Docker may need a WSL restart" >&2
fi

ubuntu_codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [ -z "$ubuntu_codename" ]; then
  echo "error: could not determine Ubuntu codename" >&2
  exit 1
fi

docker_packages=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)

conflicting_packages=(
  docker.io
  docker-doc
  docker-compose
  docker-compose-v2
  podman-docker
  containerd
  runc
)
installed_conflicting_packages=()
for package in "${conflicting_packages[@]}"; do
  if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -Fxq "install ok installed"; then
    installed_conflicting_packages+=("$package")
  fi
done

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
if [ "${#installed_conflicting_packages[@]}" -gt 0 ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y "${installed_conflicting_packages[@]}"
fi

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

architecture="$(dpkg --print-architecture)"
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_codename
Components: stable
Architectures: $architecture
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${docker_packages[@]}"

current_user="${SUDO_USER:-${USER:-$(id -un)}}"
if ! getent group docker >/dev/null 2>&1; then
  sudo groupadd docker
fi
if ! id -nG "$current_user" | tr ' ' '\n' | grep -Fxq docker; then
  add_to_docker_group="${ADD_USER_TO_DOCKER_GROUP:-}"
  if [ -z "$add_to_docker_group" ] && [ -t 0 ]; then
    echo "Docker daemon access is root-equivalent inside this WSL distro." >&2
    read -r -p "Add $current_user to the docker group for passwordless docker access? [y/N] " add_to_docker_group
  fi

  case "$add_to_docker_group" in
    1 | y | Y | yes | YES)
      sudo usermod -aG docker "$current_user"
      echo "info: added $current_user to docker group; restart WSL or run 'newgrp docker' before using docker without sudo" >&2
      ;;
    *)
      echo "info: did not add $current_user to docker group; use 'sudo docker' or rerun with ADD_USER_TO_DOCKER_GROUP=1" >&2
      ;;
  esac
fi

sudo systemctl enable --now docker.service
sudo systemctl enable --now containerd.service

docker --version
docker compose version
