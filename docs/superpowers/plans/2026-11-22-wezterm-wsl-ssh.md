# WezTerm WSL over SSH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows WezTerm opens WSL with its built-in SSH client instead of its WSL domain, so image previews (mxt, iamb) no longer pass through the pre-1.22 ConPTY that drops them (#65), as designed in `docs/superpowers/specs/2026-11-22-wsl-terminal-ssh-design.md`.

**Architecture:** A WSL-only chezmoi run script writes a dedicated key, a known_hosts file and a marked `Host wsl` block (ProxyCommand `wsl.exe -d <distro> -e nc -N 127.0.0.1 22`) into `%USERPROFILE%\.ssh\`, and authorizes the key in WSL. `wezterm.lua` registers `wezterm.default_ssh_domains()` on Windows and makes `SSH:wsl` the default domain when that host exists, else keeps the WSL domain. A hook test renders the run script for WSL and runs it against temporary homes with wslu and ssh-keyscan stubbed.

**Tech Stack:** Bash, chezmoi 2.69.1, prek 0.3.11, OpenSSH 8.9p1 (WSL Ubuntu 22.04), OpenSSH for Windows 9.5p2, WezTerm 20230712-072601-f4abf8fd (Windows), netcat-openbsd

## Global Constraints

- Public repository: no user names, distro names, host names or Windows paths of this machine in committed files. The run script resolves them at run time (`id -un`, `wslpath -w /`, `wslvar USERPROFILE`).
- Run scripts are idempotent and safe to run twice; a missing prerequisite prints `warning: ...` to stderr and exits 0 (pattern of `run_onchange_after_35-install-windows-wezterm-config.sh.tmpl`).
- The block markers are exactly `# >>> dotfiles: wezterm-wsl >>>` and `# <<< dotfiles: wezterm-wsl <<<`; the host alias is exactly `wsl`, so the WezTerm domain is `SSH:wsl`.
- File names on Windows: `%USERPROFILE%\.ssh\wezterm_wsl_ed25519` (+ `.pub`), `%USERPROFILE%\.ssh\known_hosts_wezterm_wsl`, `%USERPROFILE%\.ssh\config`.
- `docs/wezterm.md` is written in Japanese; `README.md`, `docs/current-state.md`, code comments and commit messages in English.
- Commit messages follow the repo style `type(scope): <what> so <why>`; run `prek run --all-files` before every commit.
- Work on branch `feat/wezterm-wsl-ssh` (already created from `main`, holds the spec commit); the PR targets `main`.

## Machine Facts

Recorded 2026-11-22 from WSL on the Windows host.

| Item | Value |
|---|---|
| Windows WezTerm | 20230712-072601-f4abf8fd; bundled `conpty.dll` / `OpenConsole.exe` dated 2023-07-12 |
| WSL | 3.0.5.0, `systemd=true`, sshd active on `0.0.0.0:22`, `localhostForwarding=true` |
| `wslpath -w /` | `\\wsl.localhost\<distro>\` |
| `ssh-keyscan -T 5 127.0.0.1` | three lines: `127.0.0.1 ssh-rsa …`, `127.0.0.1 ssh-ed25519 …`, `127.0.0.1 ecdsa-sha2-nistp256 …` |
| `nc` | netcat-openbsd, has `-N` |
| Windows user vs WSL user | different names, so `User` must be written |
| `%USERPROFILE%\.ssh\config` | does not exist yet |
| `ssh-keygen` into `/mnt/c` | works; the file ACL is SYSTEM, Administrators and the user (accepted by OpenSSH for Windows) |
| `wezterm.exe --config-file <probe.lua> ls-fonts --text a` | evaluates the config and prints `wezterm.log_warn` lines on stderr; `wezterm.default_ssh_domains()` exists in 20230712 |

---

### Task 1: Setup run script, its test and its prerequisites

**Files:**
- Create: `run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl`
- Create: `scripts/test-windows-wezterm-ssh.sh`
- Modify: `.pre-commit-config.yaml` (append a hook after `glazewm-window-picker`, line 78)
- Modify: `scripts/check-chezmoi-managed.sh:76` (`require_source`)
- Modify: `run_once_before_10-install-apt-packages.sh.tmpl:12-13` (package list)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: after a run on WSL, `%USERPROFILE%\.ssh\config` starts with (or keeps in place) the marked block defining `Host wsl`; Task 2's `wezterm.lua` looks for the domain `SSH:wsl` that WezTerm derives from it.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-windows-wezterm-ssh.sh`:

```bash
#!/usr/bin/env bash
# Renders run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl as on WSL
# and runs it against temporary Windows and WSL homes, with wslu and
# ssh-keyscan stubbed. Checks what it writes: the `Host wsl` block (created at
# the top, replaced in place, kept out of a config that defines the host
# itself or has a broken block), one authorized_keys line, known_hosts, and
# nothing new on a second run.
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
wsl_home="$test_tmp/home"
authorized_keys="$wsl_home/.ssh/authorized_keys"
user=$(id -un)
host_key='127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTHOSTKEY'

mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/wslvar" <<'EOF'
#!/usr/bin/env bash
[ "$1" = USERPROFILE ] && printf 'C:\\Users\\tester\n'
EOF
cat >"$test_tmp/bin/wslpath" <<EOF
#!/usr/bin/env bash
if [ "\$1" = -w ] && [ "\$2" = / ]; then
  printf '\\\\\\\\wsl.localhost\\\\TestDistro\\\\\n'
elif [ "\$1" = 'C:\\Users\\tester' ]; then
  printf '%s\n' "$windows_home"
else
  exit 1
fi
EOF
cat >"$test_tmp/bin/ssh-keyscan" <<EOF
#!/usr/bin/env bash
[ -n "\${KEYSCAN_FAIL:-}" ] && exit 1
printf '%s\n' '$host_key'
EOF
printf '#!/usr/bin/env bash\n' >"$test_tmp/bin/nc"
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
grep -Fxq '  ProxyCommand wsl.exe -d TestDistro -e nc -N 127.0.0.1 22' "$config" || fail 'the ProxyCommand must run nc -N in the distro that wslpath -w / names'
[ -f "$windows_ssh/wezterm_wsl_ed25519" ] && [ -f "$windows_ssh/wezterm_wsl_ed25519.pub" ] || fail 'the key pair must exist'
[ "$(cat "$windows_ssh/known_hosts_wezterm_wsl")" = "$host_key" ] || fail 'known_hosts must hold what ssh-keyscan printed'
key_blob=$(cut -d ' ' -f 2 "$windows_ssh/wezterm_wsl_ed25519.pub")
[ "$(head -n 1 "$authorized_keys")" = 'ssh-ed25519 AAAAEXISTINGKEY someone' ] || fail 'the existing authorized_keys line must stay intact'
[ "$(grep -c "$key_blob" "$authorized_keys")" = 1 ] || fail 'authorized_keys must hold the key once'
grep -Fq "from=\"127.0.0.1,::1\" ssh-ed25519 $key_blob" "$authorized_keys" || fail 'the key must be limited to 127.0.0.1'

# A second run changes nothing.
snapshot() {
  cat "$config" "$authorized_keys" "$windows_ssh/known_hosts_wezterm_wsl" "$windows_ssh/wezterm_wsl_ed25519" | cksum
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
  [ ! -e "$windows_ssh/wezterm_wsl_ed25519" ] || fail "no key may be created for: $content"
done

printf 'ok - WezTerm SSH setup writes the Host wsl block, key and known_hosts, and leaves configs it does not own alone\n'
```

Then: `chmod +x scripts/test-windows-wezterm-ssh.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `scripts/test-windows-wezterm-ssh.sh; echo "exit=$?"`
Expected: `…/run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl: No such file or directory` (three times) and `exit=1`.

- [ ] **Step 3: Write the run script**

Create `run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl`:

```bash
{{- if and (eq .chezmoi.os "linux") (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
#!/usr/bin/env bash
# WSL: let the Windows WezTerm open WSL over SSH. Its WSL domain runs wsl.exe
# under ConPTY, which drops image escape sequences (docs/wezterm.md). This
# authorizes a key for WezTerm here and writes, on the Windows side, the key,
# a known_hosts file and a `Host wsl` block in %USERPROFILE%\.ssh\config;
# wezterm.lua makes `SSH:wsl` the default domain once that host exists.
# sshd: {{ lookPath "sshd" }} (installing openssh-server runs this again)
set -euo pipefail

begin_marker='# >>> dotfiles: wezterm-wsl >>>'
end_marker='# <<< dotfiles: wezterm-wsl <<<'
rerun_hint='then run `chezmoi state delete-bucket --bucket=entryState` and `chezmoi apply` to run this again'

for tool in wslvar wslpath nc ssh-keygen ssh-keyscan; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "warning: $tool not found; skipping the WezTerm SSH setup" >&2
    exit 0
  fi
done

# ssh-keyscan also checks that sshd answers where the ProxyCommand connects.
host_keys=$(ssh-keyscan -T 5 127.0.0.1 2>/dev/null || true)
if [ -z "$host_keys" ]; then
  echo "warning: sshd does not answer on 127.0.0.1:22; skipping the WezTerm SSH setup. Start it with 'sudo systemctl enable --now ssh', $rerun_hint" >&2
  exit 0
fi

# wslvar runs powershell.exe, which drains stdin unless it is redirected.
windows_profile=$(wslvar USERPROFILE </dev/null 2>/dev/null || true)
if [ -z "$windows_profile" ]; then
  echo "warning: could not resolve %USERPROFILE%; skipping the WezTerm SSH setup" >&2
  exit 0
fi
windows_ssh="$(wslpath "$windows_profile")/.ssh"
config="$windows_ssh/config"

# `wslpath -w /` is \\wsl.localhost\<distro>\. SSH sessions have no
# WSL_DISTRO_NAME, and chezmoi apply runs in one after the switch.
distro=$(wslpath -w /)
distro=${distro#\\\\}
distro=${distro#*\\}
distro=${distro%%\\*}
user=$(id -un)

# Leave a config alone that defines `Host wsl` itself or has a broken block:
# counts of begin and end markers, whether `Host wsl` appears outside them, and
# whether an end marker comes first.
scan="0 0 0 0"
if [ -f "$config" ]; then
  scan=$(BEGIN_MARKER="$begin_marker" END_MARKER="$end_marker" awk '
    { line = $0; sub(/\r$/, "", line) }
    line == ENVIRON["BEGIN_MARKER"] { begins++; inside = 1; next }
    line == ENVIRON["END_MARKER"] { ends++; if (!inside) bad = 1; inside = 0; next }
    !inside {
      lower = tolower(line)
      sub(/^[ \t]+/, "", lower)
      n = split(lower, word, /[ \t=]+/)
      if (word[1] == "host") for (i = 2; i <= n; i++) if (word[i] == "wsl") own = 1
    }
    END { print begins + 0, ends + 0, own + 0, bad + 0 }
  ' "$config")
fi
read -r begins ends own bad <<<"$scan"
if [ "$own" = 1 ]; then
  echo "warning: $config defines Host wsl outside the dotfiles block; leaving it alone (WezTerm opens that host as SSH:wsl)" >&2
  exit 0
fi
if [ "$bad" = 1 ] || [ "$begins" != "$ends" ] || [ "$begins" -gt 1 ]; then
  echo "warning: $config has unmatched '$begin_marker' / '$end_marker' lines; fix them, $rerun_hint" >&2
  exit 0
fi

mkdir -p "$windows_ssh"

# Writes stdin to $1 only when the content differs.
write_if_changed() {
  cat >"$1.new"
  if [ -f "$1" ] && cmp -s "$1.new" "$1"; then
    rm -f "$1.new"
  else
    mv "$1.new" "$1"
    echo "info: wrote $1"
  fi
}

# No passphrase: the same Windows user already gets a shell here through
# wsl.exe without one. `ssh-keygen -y` cannot rebuild a lost .pub from a key
# on /mnt/c (it refuses the 0777 mode DrvFs reports), so make a new pair.
key="$windows_ssh/wezterm_wsl_ed25519"
if [ ! -f "$key" ] || [ ! -f "$key.pub" ]; then
  rm -f "$key" "$key.pub"
  ssh-keygen -q -t ed25519 -N '' -C wezterm-wsl -f "$key"
  echo "info: created $key"
fi
read -r key_type key_blob _ <"$key.pub" || true

# from= keeps the key from working over the LAN; the ProxyCommand connects
# from 127.0.0.1.
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
authorized_keys="$HOME/.ssh/authorized_keys"
if [ ! -f "$authorized_keys" ] || ! grep -qF "$key_blob" "$authorized_keys"; then
  if [ -s "$authorized_keys" ] && [ -n "$(tail -c 1 "$authorized_keys")" ]; then
    echo >>"$authorized_keys"
  fi
  printf 'from="127.0.0.1,::1" %s %s wezterm-wsl\n' "$key_type" "$key_blob" >>"$authorized_keys"
  chmod 600 "$authorized_keys"
  echo "info: authorized $key.pub in $authorized_keys"
fi

printf '%s\n' "$host_keys" | write_if_changed "$windows_ssh/known_hosts_wezterm_wsl"

# At the top: ssh takes the first value it finds for each option, so a later
# `Host *` cannot override User. The closing `Host *` keeps options that were
# at the top of the file applying to every host. nc -N closes the connection
# when WezTerm closes the pipe, so wsl.exe does not linger.
block="$begin_marker
# Written by dotfiles (run_onchange_after_37-setup-windows-wezterm-ssh.sh).
# WezTerm opens WSL through this host so its output skips ConPTY.
Host wsl
  HostName 127.0.0.1
  User $user
  IdentityFile ~/.ssh/wezterm_wsl_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile ~/.ssh/known_hosts_wezterm_wsl
  ProxyCommand wsl.exe -d $distro -e nc -N 127.0.0.1 22
# Options below apply to every host again.
Host *
$end_marker"
if [ "$begins" = 1 ]; then
  BLOCK="$block" BEGIN_MARKER="$begin_marker" END_MARKER="$end_marker" awk '
    { line = $0; sub(/\r$/, "", line) }
    line == ENVIRON["BEGIN_MARKER"] { print ENVIRON["BLOCK"]; skip = 1; next }
    line == ENVIRON["END_MARKER"] { skip = 0; next }
    !skip { print }
  ' "$config" | write_if_changed "$config"
else
  {
    printf '%s\n' "$block"
    if [ -s "$config" ]; then
      printf '\n'
      cat "$config"
    fi
  } | write_if_changed "$config"
fi
{{ end -}}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `scripts/test-windows-wezterm-ssh.sh`
Expected: `ok - WezTerm SSH setup writes the Host wsl block, key and known_hosts, and leaves configs it does not own alone`

- [ ] **Step 5: Register the hook, the source script and the packages**

In `.pre-commit-config.yaml`, append after the `glazewm-window-picker` hook (after line 78, same indentation):

```yaml
      - id: windows-wezterm-ssh
        name: WezTerm SSH setup for WSL (ssh config block, key, known_hosts)
        entry: scripts/test-windows-wezterm-ssh.sh
        language: system
        files: ^(run_onchange_after_37-setup-windows-wezterm-ssh\.sh\.tmpl|scripts/test-windows-wezterm-ssh\.sh)$
        pass_filenames: false
```

In `scripts/check-chezmoi-managed.sh`, after line 76 (`"run_onchange_after_36-install-windows-glazewm-config.sh.tmpl"`), add:

```bash
  "run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl"
```

In `run_once_before_10-install-apt-packages.sh.tmpl`, between `jq` (line 12) and `pkg-config` (line 13), add (sshd for the WezTerm SSH path, nc for its ProxyCommand):

```bash
  netcat-openbsd
  openssh-server
```

- [ ] **Step 6: Run the hook suite**

Run: `prek run --all-files`
Expected: every hook `Passed`, including `WezTerm SSH setup for WSL (ssh config block, key, known_hosts)` and `chezmoi managed paths are intentional`.

- [ ] **Step 7: Commit**

```bash
git add run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl scripts/test-windows-wezterm-ssh.sh .pre-commit-config.yaml scripts/check-chezmoi-managed.sh run_once_before_10-install-apt-packages.sh.tmpl
git commit --no-gpg-sign -m "feat(wezterm): add a WSL run script that writes the key, known_hosts and a Host wsl block, so the Windows WezTerm can reach WSL's sshd through wsl.exe without ConPTY"
```

### Task 2: Default to `SSH:wsl` on Windows, and document the path

**Files:**
- Modify: `dot_config/wezterm/wezterm.lua:56-64` (Windows branch)
- Modify: `docs/wezterm.md:19` and insert a section before `## キーバインド` (line 21)
- Modify: `docs/current-state.md:20`, after line 44, after line 130
- Modify: `README.md:246`

**Interfaces:**
- Consumes: the `Host wsl` alias from Task 1, which `wezterm.default_ssh_domains()` turns into the domain `SSH:wsl` (`config/src/ssh.rs`: `format!("SSH:{host}")`).
- Produces: `config.default_domain == "SSH:wsl"` on Windows when the host exists, else the first WSL domain's name.

- [ ] **Step 1: Record the current default domain (fallback baseline)**

Run (copies the repo config next to a probe in the Windows temp directory and lets the Windows WezTerm evaluate it):

```bash
win_tmp=$(wslpath "$(wslvar TEMP </dev/null)")
cp dot_config/wezterm/wezterm.lua "$win_tmp/wezterm-repo.lua"
cat >"$win_tmp/wezterm-probe.lua" <<'EOF'
local wezterm = require("wezterm")
local config = dofile(os.getenv("TEMP") .. "\\wezterm-repo.lua")
wezterm.log_warn("probe default_domain=" .. tostring(config.default_domain))
return config
EOF
"/mnt/c/Program Files/WezTerm/wezterm.exe" --config-file "$(wslpath -w "$win_tmp/wezterm-probe.lua")" ls-fonts --text a </dev/null 2>&1 | tr -d '\r' | grep -E 'probe|ERROR'
```

Expected: one line ending in `probe default_domain=WSL:<distro>` (the default distro), no `ERROR`. Keep `$win_tmp` and the probe for Step 3.

- [ ] **Step 2: Prefer `SSH:wsl` in `wezterm.lua`**

Replace lines 56-64 of `dot_config/wezterm/wezterm.lua`:

```lua
if is_windows then
	-- Launch into WSL by default on Windows. Use the first WSL domain (WezTerm
	-- keeps `wsl -l -v` order, which lists the default distro first) instead of
	-- hard-coding a distro name that differs per machine.
	local wsl_domains = wezterm.default_wsl_domains()
	if #wsl_domains > 0 then
		config.default_domain = wsl_domains[1].name
	end
end
```

with:

```lua
if is_windows then
	-- Launch into WSL by default on Windows. Use the first WSL domain (WezTerm
	-- keeps `wsl -l -v` order, which lists the default distro first) instead of
	-- hard-coding a distro name that differs per machine.
	local wsl_domains = wezterm.default_wsl_domains()
	if #wsl_domains > 0 then
		config.default_domain = wsl_domains[1].name
	end
	-- Once run_onchange_after_37-setup-windows-wezterm-ssh.sh has written
	-- `Host wsl` to %USERPROFILE%\.ssh\config, open WSL with WezTerm's own SSH
	-- client instead: the WSL domain runs wsl.exe under the bundled ConPTY,
	-- which predates 1.22 and drops image escape sequences (docs/wezterm.md).
	config.ssh_domains = wezterm.default_ssh_domains()
	for _, domain in ipairs(config.ssh_domains) do
		if domain.name == "SSH:wsl" then
			config.default_domain = domain.name
		end
	end
end
```

- [ ] **Step 3: Check the fallback still holds before setup**

Run (same probe, new copy of the config):

```bash
cp dot_config/wezterm/wezterm.lua "$win_tmp/wezterm-repo.lua"
"/mnt/c/Program Files/WezTerm/wezterm.exe" --config-file "$(wslpath -w "$win_tmp/wezterm-probe.lua")" ls-fonts --text a </dev/null 2>&1 | tr -d '\r' | grep -E 'probe|ERROR'
```

Expected: still `probe default_domain=WSL:<distro>`, no `ERROR` (there is no `%USERPROFILE%\.ssh\config` yet). Task 3 repeats the probe after setup and expects `SSH:wsl`. Then remove the probe files:

```bash
rm -f "$win_tmp/wezterm-repo.lua" "$win_tmp/wezterm-probe.lua"
```

- [ ] **Step 4: Document the path in `docs/wezterm.md`**

Replace line 19:

```markdown
  `default_domain` は `wsl -l -v` 先頭 (既定ディストロ) の WSL ドメインに自動で合わせる。
```

with:

```markdown
  `default_domain` は下の「WSL への接続 (Windows)」の `SSH:wsl`。まだ用意していない
  マシンでは `wsl -l -v` 先頭 (既定ディストロ) の WSL ドメインに自動で合わせる。
```

Insert before `## キーバインド` (line 21), followed by a blank line:

```markdown
## WSL への接続 (Windows)

Windows の WezTerm は、WSL に **WezTerm 内蔵の SSH クライアント** で入る
(`SSH:wsl` ドメイン)。WSL ドメインは `wsl.exe` を ConPTY の下で動かすが、この
WezTerm (20230712) が同梱している ConPTY は 1.22 より古く、Sixel や Kitty の画像の
エスケープシーケンスを捨てる。そのため mxt や iamb の画像プレビューが崩れていた
(#65)。ConPTY 1.22 を同梱しているのは WezTerm の nightly だけ。

経路は WezTerm → ProxyCommand `wsl.exe -d <distro> -e nc -N 127.0.0.1 22` → WSL の
sshd。`wsl.exe` とはパイプでつながるので ConPTY を通らない。`wsl.exe` が WSL を起動
し、接続している間は WSL を落とさない。`nc -N` はタブを閉じると接続を閉じる。
WezTerm の中で Windows の `ssh.exe` を動かすと ConPTY を通るので使わない。

WSL で `chezmoi apply` すると
`run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl` が次を用意する (2 回目以降
は何も変えない)。

- Windows 側: 鍵 `%USERPROFILE%\.ssh\wezterm_wsl_ed25519`、`known_hosts_wezterm_wsl`、
  `%USERPROFILE%\.ssh\config` 先頭の `# >>> dotfiles: wezterm-wsl >>>` から
  `# <<< dotfiles: wezterm-wsl <<<` までの `Host wsl`。鍵にパスフレーズは無い。同じ
  Windows ユーザーは `wsl.exe` で鍵無しにシェルを開けるので、入れる人は増えない
- WSL 側: `~/.ssh/authorized_keys` にその公開鍵を `from="127.0.0.1,::1"` 付きで 1 行

`wezterm.lua` は `%USERPROFILE%\.ssh\config` に `Host wsl` があれば `SSH:wsl` を既定
にし、無ければ WSL ドメインを使う。新しいウィンドウとタブから効く。

前提は、WSL で systemd が有効で、sshd が 127.0.0.1:22 で動いていること
(`openssh-server` は apt のスクリプトが入れる)。動いていなければスクリプトは警告して
何も書かない。sshd を起動したら `chezmoi state delete-bucket --bucket=entryState` の
あと `chezmoi apply` でもう一度走らせる。`%USERPROFILE%\.ssh\config` が目印の外で
`Host wsl` を定義しているときも、何も書かずに警告する (その `Host wsl` が `SSH:wsl`
として使われる)。

SSH で入ったセッションには `WSL_DISTRO_NAME` と `WSL_INTEROP` が無いが、systemd の
下なので `wslview` や `wslvar` などの Windows 連携は動く。mxt は `SSH_CONNECTION` を
見て SSH 扱いになり、WezTerm 向けに iTerm2 方式を選ぶ。

sshd が止まって入れないときは、Windows Terminal か PowerShell の `wsl.exe` で WSL に
入って直す。
```

- [ ] **Step 5: Update `docs/current-state.md` and `README.md`**

In `docs/current-state.md`, replace line 20:

```markdown
- Managed WezTerm config: chezmoi target on macOS (`darwin` only via `.chezmoiignore`), copied to `%USERPROFILE%\.wezterm.lua` from WSL
```

with:

```markdown
- Managed WezTerm config: chezmoi target on macOS (`darwin` only via `.chezmoiignore`), copied to `%USERPROFILE%\.wezterm.lua` from WSL; on Windows it opens WSL over SSH (`docs/wezterm.md`)
```

After line 44 (`- \`develop\` retired …`), add:

```markdown
- The Windows WezTerm opens WSL with its built-in SSH client (`SSH:wsl`, ProxyCommand through `wsl.exe`) instead of the WSL domain, whose bundled pre-1.22 ConPTY drops image escape sequences; `run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl` writes the key, known_hosts and the `Host wsl` block (#65)
```

After line 130 (the `run_onchange_after_36-…` entry), add:

```markdown
- `run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl` (WSL, sets up the SSH path the Windows WezTerm opens WSL with: key, `authorized_keys` line, known_hosts, `Host wsl` in `%USERPROFILE%\.ssh\config`)
```

In `README.md`, replace line 246:

```markdown
Neovim's terminal has no graphics protocol, so yazi.nvim shows no images. On WSL, yazi documents image previews only through `wezterm ssh` into WSL.
```

with:

```markdown
Neovim's terminal has no graphics protocol, so yazi.nvim shows no images. On WSL, image previews need a path without ConPTY, which is why the Windows WezTerm opens WSL over SSH (`docs/wezterm.md`).
```

- [ ] **Step 6: Run the hook suite**

Run: `prek run --all-files`
Expected: every hook `Passed`.

- [ ] **Step 7: Commit**

```bash
git add dot_config/wezterm/wezterm.lua docs/wezterm.md docs/current-state.md README.md
git commit --no-gpg-sign -m "feat(wezterm): open WSL through SSH:wsl on Windows when the setup script has written it, so image previews no longer pass through the bundled ConPTY that drops them"
```

### Task 3: Deploy on this machine and verify end to end

**Files:** none in the repository (writes `%USERPROFILE%\.ssh\*`, `%USERPROFILE%\.wezterm.lua` and `~/.ssh/authorized_keys` on this machine).

**Interfaces:**
- Consumes: the run script from Task 1 and the `wezterm.lua` from Task 2.
- Produces: verification results for the PR description.

Do not run `chezmoi apply` here: the changed apt script would run `sudo apt-get`, which waits for a password. Render and run only scripts 37 and 35 from the branch; the user's next `chezmoi apply` runs them again and changes nothing.

- [ ] **Step 1: Run the setup script from the branch**

Run: `chezmoi --source "$PWD" execute-template <run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl | bash`
Expected: four `info:` lines (created the key, authorized it, wrote `known_hosts_wezterm_wsl`, wrote `config`), no `warning:`.

- [ ] **Step 2: Run it again**

Run: `chezmoi --source "$PWD" execute-template <run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl | bash; echo "exit=$?"`
Expected: no output except `exit=0`.

- [ ] **Step 3: Connect with Windows OpenSSH through the written config**

Run:

```bash
probe=$(mktemp /tmp/wezterm-ssh-probe.XXXXXX.sh)
printf '%s\n' 'echo "ssh=${SSH_CONNECTION:+yes} distro=${WSL_DISTRO_NAME:-none}"' 'wslvar USERNAME </dev/null >/dev/null && echo interop=ok' >"$probe"
(cd "$(wslpath "$(wslvar USERPROFILE </dev/null)")" && ssh.exe -o BatchMode=yes wsl bash "$probe" </dev/null)
rm -f "$probe"
```

Expected: `ssh=yes distro=none` and `interop=ok`, no host key or permission prompt (BatchMode turns any prompt into a failure). If `ssh.exe` reports `UNPROTECTED PRIVATE KEY FILE`, compare the key's ACL with the probe in Machine Facts before changing anything.

- [ ] **Step 4: Install the WezTerm config and check the default domain**

Run: `chezmoi --source "$PWD" execute-template <run_onchange_after_35-install-windows-wezterm-config.sh.tmpl | bash`
Expected: `info: installed WezTerm config to …/.wezterm.lua`. WezTerm reloads it; open panes stay on the WSL domain, new ones use SSH.

Then run:

```bash
win_tmp=$(wslpath "$(wslvar TEMP </dev/null)")
cat >"$win_tmp/wezterm-probe.lua" <<'EOF'
local wezterm = require("wezterm")
local config = dofile(wezterm.home_dir .. "\\.wezterm.lua")
wezterm.log_warn("probe default_domain=" .. tostring(config.default_domain))
return config
EOF
"/mnt/c/Program Files/WezTerm/wezterm.exe" --config-file "$(wslpath -w "$win_tmp/wezterm-probe.lua")" ls-fonts --text a </dev/null 2>&1 | tr -d '\r' | grep -E 'probe|ERROR'
rm -f "$win_tmp/wezterm-probe.lua"
```

Expected: `probe default_domain=SSH:wsl`, no `ERROR`.

- [ ] **Step 5: Manual checks on Windows (ask the user)**

Ask the user to restart WezTerm (close every window, start it again) and report:

1. In the new window, `echo $SSH_CONNECTION` is not empty and `tmux display -p '#{client_termtype}'` prints `WezTerm …`.
2. mxt and iamb draw image previews outside tmux and inside a tmux session that only the Windows WezTerm is attached to.
3. `wslview https://example.com` opens the browser, `wslvar USERPROFILE` prints the path, and a tmux yank (OSC 52) reaches the Windows clipboard.
4. After `wsl --shutdown` from PowerShell, starting WezTerm starts WSL and connects.
5. After closing a WezTerm tab, `pgrep -af 'nc -N 127.0.0.1 22'` (from another tab) no longer lists that tab's `nc`.

Record each result. A failing check goes back to the task that owns it (Task 1: setup and connection, Task 2: domain choice) before the PR.

- [ ] **Step 6: Push and open the PR**

Write the PR body to `/tmp/wezterm-wsl-ssh-pr.md`, in Japanese like the recent PRs (#64, #77), with these sections:

- `## 概要`: the Windows WezTerm opened WSL through its WSL domain, whose bundled ConPTY (2023-07, before 1.22) drops image escape sequences, so mxt fell back to half blocks; it now opens WSL with its built-in SSH client through `wsl.exe` and `nc -N`.
- `## 変更`: one bullet per file from Tasks 1 and 2.
- `## 確認`: the hook test, the Task 3 Step 2 rerun (no output), the `ssh.exe` probe output from Step 3, the WezTerm probe output from Step 4, and the five manual results from Step 5 as written by the user.
- Last line: `Closes #65`

Then:

```bash
git push -u origin feat/wezterm-wsl-ssh
gh pr create --base main --title "feat(wezterm): open WSL over SSH on Windows so image previews skip the ConPTY that drops them" --body-file /tmp/wezterm-wsl-ssh-pr.md
rm -f /tmp/wezterm-wsl-ssh-pr.md
```
