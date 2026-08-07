#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-nixos-test.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home" "$test_tmp/repo/scripts"
touch "$test_tmp/NIXOS"
printf '%s\n' '[tools]' 'chezmoi = "2.69.1"' >"$test_tmp/repo/mise.toml"

sed "s#/etc/NIXOS#$test_tmp/NIXOS#" \
  "$repo_root/scripts/bootstrap-nixos.sh" >"$test_tmp/repo/scripts/bootstrap-nixos.sh"

cat >"$test_tmp/bin/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'compile=%s concurrency=%s\n' \
  "${MISE_NODE_COMPILE-<unset>}" \
  "${MISE_NODE_CONCURRENCY-<unset>}" >>"$MISE_LOG"
printf '%q ' "$@" >>"$MISE_ARGS_LOG"
printf '\n' >>"$MISE_ARGS_LOG"
EOF
chmod +x "$test_tmp/bin/mise" "$test_tmp/repo/scripts/bootstrap-nixos.sh"

run_bootstrap() {
  local expected=$1
  shift

  : >"$test_tmp/mise.log"
  : >"$test_tmp/mise-args.log"
  env -u MISE_NODE_COMPILE -u MISE_NODE_CONCURRENCY "$@" \
    HOME="$test_tmp/home" \
    MISE_ARGS_LOG="$test_tmp/mise-args.log" \
    MISE_LOG="$test_tmp/mise.log" \
    PATH="$test_tmp/bin:$PATH" \
    bash "$test_tmp/repo/scripts/bootstrap-nixos.sh"

  if [ ! -s "$test_tmp/mise.log" ]; then
    echo 'bootstrap must invoke mise' >&2
    exit 1
  fi

  if grep -Fvxq "$expected" "$test_tmp/mise.log"; then
    echo "expected every mise invocation to use $expected" >&2
    cat "$test_tmp/mise.log" >&2
    exit 1
  fi

  if ! grep -Fq -- '--force' "$test_tmp/mise-args.log"; then
    echo 'bootstrap must apply chezmoi non-interactively' >&2
    cat "$test_tmp/mise-args.log" >&2
    exit 1
  fi

  if ! grep -Eq -- 'install --yes chezmoi( |$)' "$test_tmp/mise-args.log"; then
    echo 'bootstrap must install chezmoi from mise.toml (no CLI @version)' >&2
    cat "$test_tmp/mise-args.log" >&2
    exit 1
  fi

  if grep -Eq -- 'chezmoi@' "$test_tmp/mise-args.log"; then
    echo 'bootstrap must not pass chezmoi@VERSION to mise' >&2
    cat "$test_tmp/mise-args.log" >&2
    exit 1
  fi
}

run_bootstrap 'compile=0 concurrency=2'
run_bootstrap 'compile=1 concurrency=7' \
  MISE_NODE_COMPILE=1 MISE_NODE_CONCURRENCY=7

printf 'ok - NixOS bootstrap uses prebuilt Node safely unless overridden\n'
