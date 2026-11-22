# ウィンドウマネージャ (macOS / AeroSpace)

macOS では [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide) を使う。キー配置とアプリの
スロットは 3 台共通で、設計は
`docs/superpowers/specs/2026-11-21-window-manager-design.md`、この Mac での調査結果と手順は
`docs/superpowers/plans/2026-11-21-wm-macos.md` にある。

## 配置

- インストール: `Brewfile` の `tap "nikitabobko/tap"` と `cask "nikitabobko/tap/aerospace"`。
  AeroSpace は homebrew/cask に無く、Homebrew 7 は tap を明示しないと third-party tap の
  cask を入れない。
- 設定: `dot_config/aerospace/aerospace.toml` を chezmoi が
  `~/.config/aerospace/aerospace.toml` に展開する (`.chezmoiignore` で darwin 以外では無視)。
  `~/.aerospace.toml` も置くと AeroSpace は曖昧として報告するので置かない。
- 設定は自動では読み直さない。`chezmoi apply` のあとに `aerospace reload-config` を実行する。

## 初回だけの手作業

1. `open -a AeroSpace` で起動し、システム設定 → プライバシーとセキュリティ →
   アクセシビリティで AeroSpace を許可する。許可した時点で既存のウィンドウがタイル配置になる。
   次回からは `start-at-login = true` によりログイン時に起動する。
2. Raycast の設定 → General → Raycast Hotkey を `⌥Space` 以外 (例: `⌘⇧Space`) にする。
   `⌥Space` は Raycast の初期値で、AeroSpace のウィンドウピッカーと衝突する。
3. 初めて `⌥Space` を押すと Raycast が "Request to run Switch Windows" と確認してくるので
   "Always Run Command" を選ぶ。

## キー

Mod は左 Option。Karabiner の "Windows-friendly" プロファイルで fn と左 Control を入れ替えて
いるので、Space の 2 つ左にあり、Windows の `Win` と同じ指の動きになる。

| 操作 | キー |
|---|---|
| workspace N へ移動 (もう一度押すと戻る) | `⌥1`..`⌥9` |
| ウィンドウを N へ送ってついていく | `⌥⇧1`..`⌥⇧9` |
| フォーカス移動 左/下/上/右 | `⌥h` `⌥j` `⌥k` `⌥l` |
| ウィンドウ移動 (2 枚なら入れ替え) | `⌥⇧h` `⌥⇧j` `⌥⇧k` `⌥⇧l` |
| 全画面の切り替え | `⌥f` |
| フローティングの切り替え | `⌥⇧Space` |
| 狭く / 広く | `⌥-` / `⌥=` |
| ウィンドウピッカー (Raycast "Switch Windows") | `⌥Space` |

## スロット

| Slot | アプリ | 備考 |
|---|---|---|
| 1 | なし | この Mac にゲームは無い。AeroSpace 起動前から開いていた他のウィンドウはここに集まる |
| 2 | Microsoft Edge (`com.microsoft.edgemac`) | 既定ブラウザ |
| 3 | WezTerm (`com.github.wez.wezterm`) | |
| 4–9 | 空き | 開いたアプリは表示中の workspace に入る |

AeroSpace 起動時に `after-startup-command` が WezTerm と Edge を開くので、2 と 3 は空にならない。

## 使えなくなる Option キー

AeroSpace が掴んだ Option の組み合わせはアプリに届かない。

- fish: `alt-h` (man ページ)、`alt-l` (トークンの一覧)、`alt-f` (単語移動。`Ctrl+→` は Karabiner
  経由で `Option+→` になるので単語移動自体は残る)。
- Neovim (LazyVim 既定): `<A-j>` / `<A-k>` (行の上下移動)。visual で選んで `:m` で代用する。
- tmux: `C-f M-1..5` のレイアウト切り替え。`C-f Space` (next-layout) を使う。
- GUI アプリで Option を押して打つ記号: `–` (`⌥-`)、`≠` (`⌥=`)、`ƒ` (`⌥f`)、`¡™£¢∞§¶•ª`
  (`⌥1..9`) など。

WezTerm のタブ (`⌘1..9`)、Karabiner の Ctrl ショートカットと単語移動 (`Option+矢印` /
`Option+Backspace`)、tmux の `C-f C-h/j/k/l` は AeroSpace が掴まないのでそのまま使える。

## WezTerm の全画面

AeroSpace を使っている間は `⌥Enter` (WezTerm の `ToggleFullScreen`) を使わない。
`native_macos_fullscreen_mode = true` によりウィンドウが macOS の別 Space に移り、
AeroSpace はそのウィンドウを並べられない (`aerospace list-windows` で
`macos_native_fullscreen` と表示される)。workspace を切り替えるたびに Space 切り替えの
アニメーションも入る。戻すには WezTerm でもう一度 `⌥Enter` を押すか、次を実行する。

```sh
aerospace macos-native-fullscreen off --window-id "$(aerospace list-windows --monitor all --app-bundle-id com.github.wez.wezterm --format '%{window-id}' | head -1)"
```

WezTerm だけの workspace ではウィンドウがすでに画面いっぱいになる。並べている最中に
広げたいときは `⌥f` (AeroSpace の全画面) を使い、ペインだけ広げたいときは tmux の `C-f z` を使う。

## macOS のウィンドウ整列キー

macOS 15 以降はウインドウ → 移動とサイズ変更 の項目を `fn+Ctrl(+Shift)+矢印` に割り当てている。
これはアプリから見ると `Ctrl(+Shift)+PageUp/PageDown/Home/End` で、WezTerm やブラウザのタブ
切り替え・入れ替え、文書の先頭・末尾への移動とぶつかる。たとえば `Ctrl+Shift+fn+↑` は「上と下」
になり、WezTerm と Edge が一瞬上下に並んで AeroSpace に戻されるだけでタブは動かない。WezTerm が
ネイティブ全画面だった頃は、全画面のウィンドウに整列が効かないのでキーがそのまま届いていた。

`scripts/configure-macos-defaults.sh` は、キーボード → キーボードショートカット → アプリの
ショートカット (`NSUserKeyEquivalents`) で次の項目を押さないキーへ移し、元のキーをアプリに返す。

| 項目 | 移し先 |
|---|---|
| 上 / 下 / 左 / 右 | `⌘⌥⌃+矢印` |
| 上と下 / 下と上 / 左と右 / 右と左 | `⌘⌥⌃⇧+矢印` |

メニュー名はアプリの言語で照合されるので、英語 (WezTerm) と日本語 (Edge など) の両方を登録する。
反映には各アプリの再起動が要る。「画面全体に表示」(`fn+Ctrl+F`) と「中央に配置」(`fn+Ctrl+C`)
はぶつかるキーが無いのでそのまま。

## 困ったとき

- ウィンドウが見当たらない: 他の workspace のウィンドウは画面の右下か左下の隅に 1px だけ
  残して隠している。`⌥Space` で探すか、`aerospace list-windows --all` で workspace を確認する。
- AeroSpace を終了すると、隠していたウィンドウはすべて画面内に戻る。
- 配置が崩れた: `aerospace flatten-workspace-tree` でその workspace の木を平らに戻す。
