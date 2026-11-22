#!/usr/bin/env bash
# Renders run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl as on WSL
# and runs it against temporary Windows and WSL homes, with wslu and
# ssh-keyscan stubbed. Checks what it writes: the `Host wsl` block (created at
# the top, replaced in place, kept out of a config that defines the host
# itself or has a broken block), instanceIdleTimeout=-1 in .wslconfig (and
# nothing at all when .wslconfig sets another value), one authorized_keys
# line, known_hosts, and nothing new on a second run.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
template="$repo_root/run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/windows-wezterm-ssh-test.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

if ! command -v chezmoi >/dev/null 2>&1; then
  echo 'chezmoi is required for this check' >&2
  exit 1
fi

fail() {
  echo "$1" >&2
  exit 1
}

render() {
  chezmoi --source "$repo_root" --override-data "$1" execute-template <"$template"
}

# Only WSL runs it; macOS has no .chezmoi.kernel, so the guard must not read it there.
for data in '{"chezmoi":{"os":"darwin"}}' '{"chezmoi":{"os":"linux","kernel":{"osrelease":"6.6.0"}}}'; do
  if [ -n "$(render "$data")" ]; then
    fail "the setup script must render empty outside WSL (data: $data)"
  fi
done
render '{"chezmoi":{"os":"linux","kernel":{"osrelease":"5.15.0-microsoft-standard-WSL2"}}}' >"$test_tmp/setup.sh"

windows_home="$test_tmp/windows-home"
windows_ssh="$windows_home/.ssh"
config="$windows_ssh/config"
wslconfig="$windows_home/.wslconfig"
wsl_home="$test_tmp/home"
authorized_keys="$wsl_home/.ssh/authorized_keys"
user=$(id -un)
ed25519_key='127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTHOSTKEY'
rsa_key='127.0.0.1 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABTESTHOSTKEY'

mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/wslvar" <<'EOF'
#!/usr/bin/env bash
[ "$1" = USERPROFILE ] && printf 'C:\\Users\\tester\n'
EOF
cat >"$test_tmp/bin/wslpath" <<EOF
#!/usr/bin/env bash
[ "\$1" = 'C:\\Users\\tester' ] || exit 1
printf '%s\n' "$windows_home"
EOF
cat >"$test_tmp/bin/ssh-keyscan" <<EOF
#!/usr/bin/env bash
[ -n "\${KEYSCAN_FAIL:-}" ] && exit 1
# ssh-keyscan asks for each key type at once, so the order changes between runs.
if [ -e "$test_tmp/keyscan-flip" ]; then
  rm "$test_tmp/keyscan-flip"
  printf '%s\n' '$ed25519_key' '$rsa_key'
else
  touch "$test_tmp/keyscan-flip"
  printf '%s\n' '$rsa_key' '$ed25519_key'
fi
EOF
chmod +x "$test_tmp/bin/"*

# Fresh homes, then the setup script; stderr goes to $test_tmp/stderr.log.
reset_homes() {
  rm -rf "$windows_home" "$wsl_home"
  mkdir -p "$windows_home" "$wsl_home"
}
run_setup() {
  HOME="$wsl_home" PATH="$test_tmp/bin:$PATH" bash "$test_tmp/setup.sh" >/dev/null 2>"$test_tmp/stderr.log"
}
# Prints the lines after the end marker.
after_block() {
  sed -n '/^# <<< dotfiles: wezterm-wsl <<<$/,$p' "$config" | tail -n +2
}

# sshd not answering: warn, write nothing.
reset_homes
KEYSCAN_FAIL=1 run_setup
grep -Fq 'sshd does not answer' "$test_tmp/stderr.log" || fail 'expected a warning when sshd does not answer'
[ -z "$(ls -A "$windows_home")" ] || fail 'nothing may be written on Windows while sshd does not answer'
[ ! -e "$authorized_keys" ] || fail 'authorized_keys must stay untouched while sshd does not answer'

# No ssh config yet: create the block, the key, known_hosts, and one
# authorized_keys line after an existing line that lacks its newline.
reset_homes
mkdir -p "$wsl_home/.ssh"
printf 'ssh-ed25519 AAAAEXISTINGKEY someone' >"$authorized_keys"
run_setup
[ "$(head -n 1 "$config")" = '# >>> dotfiles: wezterm-wsl >>>' ] || fail 'the block must start the new ssh config'
grep -Fxq "  User $user" "$config" || fail 'the block must log in as the WSL user'
grep -Fxq '  HostName 127.0.0.1' "$config" || fail 'the block must connect to 127.0.0.1'
! grep -Fq ProxyCommand "$config" || fail 'the block must not use a ProxyCommand, which WezTerm stalls on Windows'
[ "$(cat "$wslconfig")" = "$(printf '[general]\ninstanceIdleTimeout=-1')" ] || fail 'a missing .wslconfig must be created with instanceIdleTimeout=-1'
[ -f "$windows_ssh/wezterm_wsl_ed25519" ] && [ -f "$windows_ssh/wezterm_wsl_ed25519.pub" ] || fail 'the key pair must exist'
[ "$(cat "$windows_ssh/known_hosts_wezterm_wsl")" = "$(printf '%s\n' "$ed25519_key" "$rsa_key")" ] || fail 'known_hosts must hold the sorted ssh-keyscan lines'
key_blob=$(cut -d ' ' -f 2 "$windows_ssh/wezterm_wsl_ed25519.pub")
[ "$(head -n 1 "$authorized_keys")" = 'ssh-ed25519 AAAAEXISTINGKEY someone' ] || fail 'the existing authorized_keys line must stay intact'
[ "$(grep -c "$key_blob" "$authorized_keys")" = 1 ] || fail 'authorized_keys must hold the key once'
grep -Fq "from=\"127.0.0.1,::1\" ssh-ed25519 $key_blob" "$authorized_keys" || fail 'the key must be limited to 127.0.0.1'

# A second run changes nothing.
snapshot() {
  cat "$config" "$wslconfig" "$authorized_keys" "$windows_ssh/known_hosts_wezterm_wsl" "$windows_ssh/wezterm_wsl_ed25519" | cksum
}
before=$(snapshot)
run_setup
[ "$(snapshot)" = "$before" ] || fail 'a second run must not change anything'

# An existing config: the block goes on top, and the old lines follow a
# closing `Host *`, so options that applied to every host still do.
reset_homes
mkdir -p "$windows_ssh"
printf 'ServerAliveInterval 60\n\nHost foo\n  HostName foo.example\n' >"$test_tmp/original"
cp "$test_tmp/original" "$config"
run_setup
[ "$(head -n 1 "$config")" = '# >>> dotfiles: wezterm-wsl >>>' ] || fail 'the block must go above an existing config'
[ "$(grep -B 1 -Fx '# <<< dotfiles: wezterm-wsl <<<' "$config" | head -n 1)" = 'Host *' ] || fail 'the block must end with Host *'
diff <(after_block | tail -n +2) "$test_tmp/original" >/dev/null || fail 'the existing config must follow the block unchanged'

# A marked block further down is replaced where it is.
reset_homes
mkdir -p "$windows_ssh"
printf 'Host foo\n  HostName foo.example\n# >>> dotfiles: wezterm-wsl >>>\nHost wsl\n  User olduser\n# <<< dotfiles: wezterm-wsl <<<\nHost bar\n  HostName bar.example\n' >"$config"
run_setup
[ "$(head -n 2 "$config")" = "$(printf 'Host foo\n  HostName foo.example')" ] || fail 'lines above a marked block must stay above it'
[ "$(after_block)" = "$(printf 'Host bar\n  HostName bar.example')" ] || fail 'lines below a marked block must stay below it'
! grep -Fq olduser "$config" || fail 'the marked block must be replaced'
grep -Fxq "  User $user" "$config" || fail 'the replaced block must log in as the WSL user'

# .wslconfig: a new [general] at the end, the key right under an existing
# [general], and a file that already says -1 (CRLF, other case) left alone.
check_wslconfig() {
  reset_homes
  # Both arguments are printf formats.
  printf "$1" >"$wslconfig"
  printf "$2" >"$test_tmp/expected"
  run_setup
  cmp -s "$wslconfig" "$test_tmp/expected" || fail "unexpected .wslconfig for: $1"
  [ -f "$config" ] || fail "the ssh config must be written for .wslconfig: $1"
}
check_wslconfig '[wsl2]\nmemory=24GB\n' '[wsl2]\nmemory=24GB\n\n[general]\ninstanceIdleTimeout=-1\n'
check_wslconfig '[wsl2]\nmemory=24GB' '[wsl2]\nmemory=24GB\n\n[general]\ninstanceIdleTimeout=-1\n'
check_wslconfig '[general]\nfoo=bar\n[wsl2]\nmemory=24GB\n' '[general]\ninstanceIdleTimeout=-1\nfoo=bar\n[wsl2]\nmemory=24GB\n'
check_wslconfig '[General]\r\nInstanceIdleTimeout = -1\r\n' '[General]\r\nInstanceIdleTimeout = -1\r\n'

# Another instanceIdleTimeout would stop WSL under the SSH sessions: write nothing.
reset_homes
printf '[general]\ninstanceIdleTimeout=60000\n' >"$wslconfig"
cp "$wslconfig" "$test_tmp/original"
run_setup
cmp -s "$wslconfig" "$test_tmp/original" || fail 'a .wslconfig with another instanceIdleTimeout must stay unchanged'
grep -Fq 'instanceIdleTimeout' "$test_tmp/stderr.log" || fail 'expected a warning about instanceIdleTimeout'
[ ! -e "$config" ] && [ ! -e "$windows_ssh/wezterm_wsl_ed25519" ] || fail 'nothing may be written while instanceIdleTimeout is not -1'

# A config that defines `Host wsl` itself (CRLF, as Windows editors save it),
# or has a begin marker without an end marker, is left alone.
for content in 'Host github.com wsl\r\n  User someone\r\n' '# >>> dotfiles: wezterm-wsl >>>\nHost wsl\n'; do
  reset_homes
  mkdir -p "$windows_ssh"
  # Each case is a printf format, so \r\n becomes CRLF.
  printf "$content" >"$config"
  cp "$config" "$test_tmp/original"
  run_setup
  cmp -s "$config" "$test_tmp/original" || fail "the config must stay unchanged: $content"
  grep -Fq 'warning:' "$test_tmp/stderr.log" || fail "expected a warning for: $content"
  [ ! -e "$windows_ssh/wezterm_wsl_ed25519" ] && [ ! -e "$wslconfig" ] || fail "no key or .wslconfig may be written for: $content"
done

printf 'ok - WezTerm SSH setup writes the Host wsl block, .wslconfig, key and known_hosts, and leaves configs it does not own alone\n'
