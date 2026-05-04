# Dotfiles Inventory

## 対象

新 PC の WSL Ubuntu で常用する設定だけを、この public chezmoi repo に取り込む。

優先対象:

- `fish`
- bash startup files
- `tmux`
- `nvim`

対象外:

- browser state
- cache, history, local database
- token, key, certificate
- project-specific runtime
- Windows GUI tool config

## fish

関連 shell startup files:

- `~/.bash_profile`
- `~/.bashrc`
- `~/.profile`

現行ファイル:

- `~/.config/fish/config.fish`
- `~/.config/fish/fish_plugins`
- `~/.config/fish/completions/fisher.fish`
- `~/.config/fish/functions/fisher.fish`
- `~/.config/fish/functions/bass.fish`
- `~/.config/fish/functions/__bass.py`
- `~/.config/fish/conf.d/nix.fish`
- `~/.config/fish/conf.d/rustup.fish`
- `~/.config/fish/fish_variables`

取り込み結果:

- `config.fish`: `~/.bashrc` source を廃止し、fish native config に整理済み。
- `fish_plugins`: `jorgebucaran/fisher` のみ管理。`bass` は不要化したため除外。
- `conf.d/nix.fish`: Nix が存在する場合だけ source。
- `conf.d/rustup.fish`: cargo env が存在する場合だけ source。

除外:

- `fish_variables`: machine-local state を含みやすいので管理しない。
- private tunnel / host 固有 daemon 起動: template 化または private config へ移す。

要修正:

- `~/.bash_profile` の `exec fish` は、default shell を `chsh` する方針なら不要。bash から fish に逃がす暫定設定として扱う。
- `.profile` に fish 構文の `set PATH ...` が混ざっているため、新 repo では再利用しない。
- `fish_variables` は引き続き取り込まない。

`~/.bashrc` から fish へ移す候補:

- `REPOS`, `WREPOS`, `WHOME`, `DOWNLOAD`, `TRASH`, `SAVE`
- `clip`, `paste`, `python`, `pip`, `mtu`, `ll`, `la`, `l`
- `gh completion`
- `GPG_TTY`
- `TYPST_FONT_PATHS`
- browser helper
- WSL 向け Windows PATH helper
- `mise`, `starship`, `zoxide`, `pnpm`, `cargo`, `elan` などの user-level tool activation

`~/.bashrc` から移さない候補:

- `CARGO_HTTP_DEBUG`, `CARGO_LOG`, `RUST_LOG`: debug 用。常時 export しない。
- `compro.sh`, `ac-rs/compete`: project-specific。
- `jikka`, `tqklib`, `antlr4`, `grun`: project-specific または必要時 install。
- Java, GHCup, Poetry, Herd/PHP, Dotnet, Komorebi: 常用判断後に `mise`/project 側へ移す。
- `DOCKER_BUILDKIT=0`, `COMPOSE_DOCKER_CLI_BUILD=0`: 古い workaround の可能性があるため再検討。
- private host/user path を含む Windows path は template または WSL 判定付きにする。

## tmux

現行ファイル:

- `~/.tmux.conf`
- `~/.tmux/new-session`

古い dotfiles 参照:

- `../dotfiles/ubuntu/.tmux.conf`
- `../dotfiles/ubuntu/.tmux/new-session`
- `../dotfiles/ubuntu/.tmux/new-session-isucon`
- `../dotfiles/ubuntu/.tmux/plugins/tpm/...`

取り込み結果:

- `.tmux.conf`: keybind, layout, mouse, copy-mode, popup, WSL clipboard integration を取り込み済み。
- `.tmux/new-session`: 初期 pane layout を取り込み済み。

除外:

- `~/.tmux/plugins/tpm` の clone 済み実体
- build artifact や plugin generated files
- `new-session-isucon` は project/event-specific なので必要になったら別扱い

要修正:

- TPM は `run_once_before_20-install-tmux-plugin-manager.sh` で clone する。repo に vendor しない。
- `wifi`, `battery` command は削除済み。
- `clip.exe` copy は WSL 判定付きで残した。
- CRLF は LF に正規化済み。

## nvim

現行ファイル:

- `~/.config/nvim/init.lua`
- `~/.config/nvim/lazyvim.json`
- `~/.config/nvim/lazy-lock.json`
- `~/.config/nvim/stylua.toml`
- `~/.config/nvim/lua/config/*.lua`
- `~/.config/nvim/lua/plugins/*.lua`
- `~/.config/nvim/.neoconf.json`
- `~/.config/nvim/.gitignore`
- `~/.config/nvim/README.md`
- `~/.config/nvim/LICENSE`

取り込み結果:

- `init.lua`
- `lazyvim.json`
- `lazy-lock.json`
- `stylua.toml`
- `.neoconf.json`
- `lua/config/`
- `lua/plugins/`

除外:

- plugin cache
- session/state/cache files
- local workspace config
- generated runtime files

要修正:

- `lua/plugins/example.lua` は LazyVim sample なので除外済み。
- SKK dictionary path は package install とセットで扱う。
- Firenvim は Windows/browser 側依存があるため optional plugin として残す。
- Quarto/Jupyter 系 plugin は project-specific 寄り。常用なら残し、依存は project 側に寄せる。

## 旧 dotfiles の扱い

`../dotfiles` は危険な state file が多いので丸ごと移植しない。

見つかっている除外対象:

- browser state
- `gh/hosts.yml`
- token files
- certificate / key
- `chezmoistate.boltdb`
- history/cache/database
- service generated config

## 次の取り込み順

1. shell startup: `~/.bashrc`, `~/.bash_profile`, `~/.profile` を分解し、fish config に統合する方針を確定する。
2. `tmux`: ファイル数が少なく、公開リスクが低い。TPM install script を先に作る。取り込み済み。
3. `fish`: private daemon 起動と hard-coded path を外してから取り込む。取り込み済み。
4. `nvim`: ファイル数が多いため、`example.lua` など不要物を削って取り込む。取り込み済み。
