#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
install_script="$repo_root/run_after_50-install-agent-clis.sh"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/agent-cli-install-test.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/absent-bin" "$test_tmp/present-bin" "$test_tmp/home"

cat >"$test_tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url=""
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf '%s\n' "$url" >>"$CURL_LOG"

if [ "${CURL_FAIL:-0}" = "1" ]; then
  exit 22
fi

cat >"$out" <<'STUB'
#!/bin/sh
printf '%s\n' "$0" >>"$INSTALLER_LOG"
STUB
EOF
chmod +x "$test_tmp/bin/curl"

for stub in omp claude; do
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$test_tmp/present-bin/$stub"
  chmod +x "$test_tmp/present-bin/$stub"
done

run_install() {
  local path_dir=$1
  local curl_fail=${2:-0}

  : >"$test_tmp/curl.log"
  : >"$test_tmp/installer.log"
  : >"$test_tmp/stderr.log"

  env -i \
    HOME="$test_tmp/home" \
    PATH="$path_dir:$test_tmp/bin:/usr/bin:/bin" \
    CURL_LOG="$test_tmp/curl.log" \
    INSTALLER_LOG="$test_tmp/installer.log" \
    CURL_FAIL="$curl_fail" \
    bash "$install_script" 2>"$test_tmp/stderr.log"
}

# Missing CLIs are installed from their upstream installers.
run_install "$test_tmp/absent-bin"

if ! grep -Fxq 'https://omp.sh/install' "$test_tmp/curl.log"; then
  echo 'install script must fetch the omp installer when omp is missing' >&2
  cat "$test_tmp/curl.log" >&2
  exit 1
fi

if ! grep -Fxq 'https://claude.ai/install.sh' "$test_tmp/curl.log"; then
  echo 'install script must fetch the Claude Code installer when claude is missing' >&2
  cat "$test_tmp/curl.log" >&2
  exit 1
fi

for expected in omp-install.sh claude-install.sh; do
  if ! grep -Fq "$expected" "$test_tmp/installer.log"; then
    echo "install script must run the downloaded $expected" >&2
    cat "$test_tmp/installer.log" >&2
    exit 1
  fi
done

# Already-installed CLIs self-update, so reapplying must not reinstall them.
run_install "$test_tmp/present-bin"

if [ -s "$test_tmp/curl.log" ]; then
  echo 'install script must not download installers when the CLIs already exist' >&2
  cat "$test_tmp/curl.log" >&2
  exit 1
fi

# A failed download warns without aborting chezmoi apply.
if ! run_install "$test_tmp/absent-bin" 1; then
  echo 'install script must exit 0 when an installer download fails' >&2
  cat "$test_tmp/stderr.log" >&2
  exit 1
fi

if [ -s "$test_tmp/installer.log" ]; then
  echo 'install script must not run an installer that failed to download' >&2
  cat "$test_tmp/installer.log" >&2
  exit 1
fi

if ! grep -Fq 'failed to download' "$test_tmp/stderr.log"; then
  echo 'install script must warn when an installer download fails' >&2
  cat "$test_tmp/stderr.log" >&2
  exit 1
fi

# A warned-but-successful exit must not retire the script: chezmoi has to run it
# again on the next apply so a transient download failure is retried. This is
# what a `run_once_` script would get wrong.
chezmoi_bin="$(command -v chezmoi || true)"
if [ -z "$chezmoi_bin" ]; then
  echo 'chezmoi is required for this check' >&2
  exit 1
fi

mkdir -p "$test_tmp/source" "$test_tmp/dest"
cp "$install_script" "$test_tmp/source/$(basename "$install_script")"

: >"$test_tmp/curl.log"
for _ in 1 2; do
  env -i \
    HOME="$test_tmp/dest" \
    PATH="$test_tmp/absent-bin:$test_tmp/bin:/usr/bin:/bin" \
    CURL_LOG="$test_tmp/curl.log" \
    INSTALLER_LOG="$test_tmp/installer.log" \
    CURL_FAIL=1 \
    "$chezmoi_bin" --source "$test_tmp/source" --destination "$test_tmp/dest" apply \
    2>>"$test_tmp/apply-stderr.log"
done

attempts="$(wc -l <"$test_tmp/curl.log" | tr -d ' ')"
if [ "$attempts" -ne 4 ]; then
  echo "chezmoi must rerun the install script on every apply (expected 4 download attempts, got $attempts)" >&2
  cat "$test_tmp/curl.log" >&2
  exit 1
fi

printf 'ok - agent CLI install script installs what is missing, warns instead of failing, and stays retriable\n'
