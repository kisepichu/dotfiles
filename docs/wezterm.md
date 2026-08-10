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

- QuickSelect (画面内の URL / ハッシュ / パスなどを素早く選択・コピー):
  WezTerm 側は **`F13`** にバインド。macOS では Karabiner が
  **物理 `fn` + `Shift` + `Space`** を `F13` に写す (下記参照)。
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

### QuickSelect を `Ctrl+Shift+Space` にバインドできない理由 (macOS)

macOS 26 (Tahoe) の HIToolbox は `Ctrl+Space` (`symbolichotkey` ID 60,
「前の入力ソースを選択」) を起点として入力ソースピッカーを開き、直後は
`Ctrl+Shift+Space` を「逆方向サイクル」として **ハードコードで消費** する。
この挙動は `System Settings > Keyboard > Keyboard Shortcuts` にも
`defaults`/`symbolichotkeys` にも露出しておらず、有効化されたピッカーが残って
いる短い時間帯は WezTerm には Ctrl+Shift+Space が一切届かない (Karabiner で
fn を control に写した後も同様)。単発で押した場合も HIToolbox が瞬間的に
イベントを吸って何も起きないように見える。

そのため QuickSelect は WezTerm 側で **`F13`** にバインドし、Karabiner の
`complex_modifications` で `Ctrl+Shift+Space` を `F13` に写している
(`dot_config/karabiner/karabiner.json`)。F13 は Mac 標準キーボードに物理キー
が無く macOS 側の予約も無いので確実に届く。ユーザから見た打鍵は従来通り
`fn/Globe + Shift + Space` のまま変わらない。

Karabiner のルール抜粋:

```
from: spacebar with mandatory [control, shift]
to:   f13
```

Karabiner は `simple_modifications` を complex より **先に** 評価するため、
物理 `fn` キーは先に `left_control` へ変換され、この complex ルールに到達する
時点で `[control, shift]` になっている。物理 `fn+Shift+Space` はここで
F13 に変換され、macOS の Ctrl+Shift+Space インターセプトを完全に回避できる。
副作用として、他のアプリで Ctrl+Shift+Space を使う「入力ソース逆方向サイクル」
機能もこの環境では発火しなくなる (ユーザは通常 `Ctrl+Space` の連打だけを使う
ため許容)。

`macos_forward_to_ime_modifier_mask = "SHIFT"` は他の Ctrl+Shift 系キーが
IME に食われないよう残してある (QuickSelect 単体には不要になったが汎用対策)。
