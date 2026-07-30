#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/dot_local/bin/executable_cloudflared-access-ssh-proxy"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/cloudflared-proxy-test.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/runtime"

cat >"$test_tmp/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'OpenSSH_9.9, test build\n' >&2
EOF

cat >"$test_tmp/bin/cloudflared" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$CLOUDFLARED_ARGS_LOG"
cat >/dev/null
EOF

chmod +x "$test_tmp/bin/ssh" "$test_tmp/bin/cloudflared"

export CLOUDFLARED_ARGS_LOG="$test_tmp/cloudflared-args.log"

if ! (
  umask 0177
  PATH="$test_tmp/bin:$PATH" TMPDIR="$test_tmp/runtime" \
    "$helper" ssh.example.test </dev/null
); then
  echo "helper failed with ssh-copy-id's inherited umask 0177" >&2
  exit 1
fi

grep -Fxq 'access tcp --hostname ssh.example.test' "$CLOUDFLARED_ARGS_LOG"
printf 'ok - cloudflared SSH proxy supports restrictive inherited umask\n'
