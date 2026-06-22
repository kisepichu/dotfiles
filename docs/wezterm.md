# WezTerm 設定

WezTerm の設定は `dot_config/wezterm/wezterm.lua` で一元管理する。OS 判定
(`wezterm.target_triple`) で macOS / Windows の差分を吸収しているので、同じファ
イルを両方で使える。

## 配置

- **macOS**: chezmoi が `~/.config/wezterm/wezterm.lua` に展開する
  (`.chezmoiignore` で darwin 以外では無視)。
- **Windows (WSL のメイン環境)**: WSL の WezTerm は Windows ホスト側で動くため
  chezmoi (WSL/macOS の home で動作) からは配置できない。Windows 側で次のいずれか:
  - このリポジトリの `dot_config/wezterm/wezterm.lua` を
    `C:\Users\<user>\.config\wezterm\wezterm.lua` または
    `C:\Users\<user>\.wezterm.lua` にコピー、または
  - 1 行だけの `.wezterm.lua` を置いて本体を `dofile` で読み込む。

## キーバインド

- `Ctrl+Shift+Space`: QuickSelect (画面内の URL / ハッシュ / パスなどを素早く選択
  ・コピー)。
- `Ctrl+Arrow`: WezTerm 側では **あえてバインドしない**。デフォルトの CSI シーケン
  スをそのまま端末へ送り、tmux (prefix `C-f` のあと `C-Arrow`) で pane swap させる
  ため。

### macOS で Ctrl+Arrow が tmux に届かない場合

macOS は標準で Mission Control が `Ctrl+←` / `Ctrl+→` を「スペースを左右に移動」に
割り当てており、端末に届かない。`scripts/configure-macos-defaults.sh` がこの 2 つ
(symbolichotkey ID 79 / 81) を無効化する。手動で行う場合:

```sh
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 79 "{ enabled = 0; }"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 81 "{ enabled = 0; }"
```

反映にはログアウト、または `activateSettings -u` の実行が必要。
