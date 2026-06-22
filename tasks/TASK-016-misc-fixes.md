# TASK-016: 細かい修正まとめ (wezterm 管理 / fish env / tmux zoom)

## 参照仕様

- User memo on 2026-06-22: dotfiles の細かい修正をまとめて対応。タスク・PR は一つにまとめる。

## 対応項目

1. **wezterm.lua 管理**: WezTerm 設定をリポジトリ管理下に置く (これまで未管理)。
2. **mac wezterm Ctrl+Shift+Space**: QuickSelect モードに割り当て。
3. **mac nvim pane フォーカス時にたまに zoom されない**: tmux の auto-zoom フックが
   macOS では発火しない問題を修正。
4. **`alias vim=nvim`**: fish に追加。
5. **`EDITOR=nvim`**: fish に追加。`BROWSER` は既に WSL=`wslview` / macOS=`open`
   で設定済み。
6. **`export PATH="$HOME/.nix-profile/bin:$PATH"`**: nix profile script が未 export
   でも `~/.nix-profile/bin` が PATH に乗るようフォールバックを追加。
7. **fish plugin `bass`**: 再導入 (`edc/bass`)。
8. **mac `C-f C-矢印` で pane swap にならない**: tmux 側は設定済み (dot_tmux.conf:40-43)。
   根本原因は macOS Mission Control が `Ctrl+←/→` を奪っていること。

## 調査結果

- **tmux auto-zoom (項目 3)**: `pane-focus-in` フックが `ps -o comm=` の出力を
  `case "$cmd" in nvim|vim)` で判定していた。macOS の `ps -o comm=` は実行ファイルの
  **フルパス** を返す (例: `/Users/.../mise/installs/neovim/.../bin/nvim`) ため、Linux
  と違ってマッチせず zoom されない。`basename` を取って判定するよう修正。
- **C-f C-矢印 (項目 8)**: tmux 設定は正しい。macOS の Mission Control が標準で
  `Ctrl+←` (ID 79) / `Ctrl+→` (ID 81) を「スペース移動」に割り当てており、端末まで
  届かないのが原因。WezTerm はデフォルトで CSI を送出するため WezTerm 側の変更は不要。

## 修正内容

- `dot_config/wezterm/wezterm.lua` (新規): OS 判定で Mac/Windows 両対応。
  appearance + `Ctrl+Shift+Space` = QuickSelect。Ctrl+Arrow はあえて未バインド。
- `.chezmoiignore`: darwin 以外で `/.config/wezterm/` を無視 (karabiner と同様)。
- `docs/wezterm.md` (新規): 配置方法・キーバインド・macOS Mission Control 無効化手順。
- `scripts/configure-macos-defaults.sh`: Mission Control の `Ctrl+←/→`
  (symbolichotkey 79/81) を無効化。`cfprefsd` kill + `activateSettings -u` で即時反映。
- `dot_config/fish/config.fish`: `EDITOR=nvim` (nvim がある場合)、`alias vim=nvim`
  (interactive かつ nvim がある場合) を追加。
- `dot_config/fish/conf.d/nix.fish`: `~/.nix-profile/bin` PATH フォールバックを追加。
- `dot_config/fish/fish_plugins`: `edc/bass` を追加。
- `dot_tmux.conf`: auto-zoom フックで `cmd` を `basename` してから判定。
- `docs/dotfiles-inventory.md`: bass 再導入を反映。

## チェックリスト

- [x] wezterm.lua 作成・chezmoi 管理 (darwin のみ展開)
- [x] Ctrl+Shift+Space = QuickSelect
- [x] tmux auto-zoom を macOS 対応 (basename 判定)
- [x] `alias vim=nvim`
- [x] `EDITOR=nvim`
- [x] nix-profile PATH フォールバック
- [x] fish plugin `bass` 追加
- [x] macOS Mission Control Ctrl+Arrow 無効化
- [x] docs / inventory 更新
- [ ] 実機確認 (Mac: Ctrl+Shift+Space, C-f C-矢印, nvim pane zoom)

## 完了条件

- [x] 上記 8 項目のうち、自動化可能なものをコードに反映
- [ ] Mac 実機で C-f C-矢印 の pane swap / nvim pane の auto-zoom / QuickSelect が動作

## 作業ログ

- 2026-06-22: 調査・実装。wezterm.lua 新規作成、tmux zoom フックの macOS 不発を
  `ps -o comm=` フルパス問題として特定し basename 判定に修正。fish に EDITOR/vim alias/
  nix PATH fallback/bass、macOS defaults に Mission Control 無効化を追加。
