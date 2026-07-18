#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-nixos-test.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home"
touch "$test_tmp/NIXOS"

sed "s#/etc/NIXOS#$test_tmp/NIXOS#" \
  "$repo_root/scripts/bootstrap-nixos.sh" >"$test_tmp/bootstrap-nixos.sh"

cat >"$test_tmp/bin/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${MISE_NODE_CONCURRENCY-<unset>}" >>"$MISE_LOG"
EOF
chmod +x "$test_tmp/bin/mise"

run_bootstrap() {
  local expected=$1
  shift

  : >"$test_tmp/mise.log"
  env -u MISE_NODE_CONCURRENCY "$@" \
    HOME="$test_tmp/home" \
    MISE_LOG="$test_tmp/mise.log" \
    PATH="$test_tmp/bin:$PATH" \
    bash "$test_tmp/bootstrap-nixos.sh"

  if [ ! -s "$test_tmp/mise.log" ]; then
    echo 'bootstrap must invoke mise' >&2
    exit 1
  fi

  if grep -Fvxq "$expected" "$test_tmp/mise.log"; then
    echo "expected every mise invocation to use Node concurrency $expected" >&2
    cat "$test_tmp/mise.log" >&2
    exit 1
  fi
}

run_bootstrap 2
run_bootstrap 7 MISE_NODE_CONCURRENCY=7

printf 'ok - NixOS bootstrap bounds Node compilation unless overridden\n'
