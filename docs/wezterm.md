# WezTerm 設定

WezTerm の設定は `dot_config/wezterm/wezterm.lua` で一元管理する。OS 判定
(`wezterm.target_triple`) で macOS / Windows の差分を吸収しているので、同じファ
イルを両方で使える。

## 配置

- **macOS**: chezmoi が `~/.config/wezterm/wezterm.lua` に展開する
  (`.chezmoiignore` で darwin 以外では無視)。
- **Windows (WSL のメイン環境)**: WSL の WezTerm は Windows ホスト側で動くため
  chezmoi の home 外にある。WSL で `chezmoi apply` すると
  `run_onchange_after_35-install-windows-wezterm-config.sh.tmpl` が
  `%USERPROFILE%\.wezterm.lua` にコピーする (このファイルが変わったときだけ再実行)。
  WezTerm は `~/.wezterm.lua` を最優先で読む (`config/src/config.rs`。公式ドキュメン
  トの図は `~/.config/wezterm` 優先と書いているが実装は逆)。初回に既存の手書き設定が
  あれば `.wezterm.lua.pre-dotfiles` に退避する。Windows 側で直接編集しても次のコピー
  で上書きされるので、変更は repo 側で行う。
  `default_domain` は下の「WSL への接続 (Windows)」の `SSH:wsl`。まだ用意していない
  マシンでは `wsl -l -v` 先頭 (既定ディストロ) の WSL ドメインに自動で合わせる。

## WSL への接続 (Windows)

Windows の WezTerm は、WSL に **WezTerm 内蔵の SSH クライアント** で入る
(`SSH:wsl` ドメイン)。WSL ドメインは `wsl.exe` を ConPTY の下で動かすが、この
WezTerm (20230712) が同梱している ConPTY は 1.22 より古く、Sixel や Kitty の画像の
エスケープシーケンスを捨てる。そのため mxt や iamb の画像プレビューが崩れていた
(#65)。ConPTY 1.22 を同梱しているのは WezTerm の nightly だけ。

経路は WezTerm → TCP `127.0.0.1:22` (WSL の `localhostForwarding`) → WSL の sshd で、
ConPTY を通らない。WezTerm の中で Windows の `ssh.exe` を動かすと ConPTY を通るので
使わない。

`wsl.exe` を ProxyCommand にする経路は使えない。Windows の WezTerm は ProxyCommand の
stdin と stdout に同じソケットを 1 つ渡し、そのソケットは同期 I/O 用
(non-overlapped) なので、Windows は読み書きを 1 つずつしか処理しない。`wsl.exe` が
stdin を読もうと待つ間は stdout への書き込みも止まり、鍵交換の途中で止まって
`Timeout connecting to 127.0.0.1` になる (`main` も同じ。
[wezterm#7959](https://github.com/wezterm/wezterm/issues/7959))。

TCP の経路には WSL を起こすものが無いので、`wezterm.lua` の `gui-startup` で
WezTerm の起動時に `wsl.exe -d <既定ディストロ> -e true` を走らせ、Windows 側の
`127.0.0.1:22` が応答するまで最大 15 秒待ってから最初のウィンドウを開く。WSL は
`wsl.exe` のセッションが無くなると 15 秒後に distro ごと止める (SSH のセッションは
数えない) ので、`%USERPROFILE%\.wslconfig` に `[general] instanceIdleTimeout=-1` を
入れる。WSL は自分では止まらなくなる (全 distro)。代わりに、Windows の端末を全部
閉じても mac からの SSH は切れない。WSL はこの設定を起動時に読むので、書いたあと
一度 Windows から `wsl --shutdown` する (WSL のセッションがすべて終わる)。

WSL で `chezmoi apply` すると
`run_onchange_after_37-setup-windows-wezterm-ssh.sh.tmpl` が次を用意する (2 回目以降
は何も変えない)。

- Windows 側: 鍵 `%USERPROFILE%\.ssh\wezterm_wsl_ed25519`、`known_hosts_wezterm_wsl`、
  `%USERPROFILE%\.ssh\config` 先頭の `# >>> dotfiles: wezterm-wsl >>>` から
  `# <<< dotfiles: wezterm-wsl <<<` までの `Host wsl`、`%USERPROFILE%\.wslconfig` の
  `instanceIdleTimeout=-1`。鍵にパスフレーズは無い。同じ Windows ユーザーは `wsl.exe`
  で鍵無しにシェルを開けるので、入れる人は増えない
- WSL 側: `~/.ssh/authorized_keys` にその公開鍵を `from="127.0.0.1,::1"` 付きで 1 行

`wezterm.lua` は `%USERPROFILE%\.ssh\config` に `Host wsl` があれば `SSH:wsl` を既定
にし、無ければ WSL ドメインを使う。新しいウィンドウとタブから効く。

前提は、WSL で systemd が有効で、sshd が 127.0.0.1:22 で動いていること
(`openssh-server` は apt のスクリプトが入れる)。動いていなければスクリプトは警告して
何も書かない。sshd を起動したら `chezmoi state delete-bucket --bucket=entryState` の
あと `chezmoi apply` でもう一度走らせる。次のときも何も書かずに警告する。

- `%USERPROFILE%\.ssh\config` が目印の外で `Host wsl` を定義している (その `Host wsl`
  が `SSH:wsl` として使われる)
- `%USERPROFILE%\.wslconfig` が `instanceIdleTimeout` を `-1` 以外にしている (SSH だけ
  では WSL が止まり tmux も消えるので、WSL ドメインのままにする)

SSH で入ったセッションには `WSL_DISTRO_NAME` と `WSL_INTEROP` が無いが、systemd の
下なので `wslview` や `wslvar` などの Windows 連携は動く。mxt は `SSH_CONNECTION` を
見て SSH 扱いになり、WezTerm 向けに iTerm2 方式を選ぶ。

WezTerm を開いたまま `wsl --shutdown` すると、新しいタブはつながらない。WezTerm を
起動し直すと `gui-startup` が WSL を起こす。sshd が止まって入れないときは、Windows
Terminal か PowerShell の `wsl.exe` で WSL に入って直す。

## キーバインド

- QuickSelect (画面内の URL / ハッシュ / パス / UUID などを素早く選択・コピー):
  Windows は WezTerm 既定の **`Ctrl+Shift+Space`**。macOS では WezTerm 側を
  **`F13`** にバインドし、Karabiner が **物理 `fn` + `Shift` + `Space`** を
  `F13` に写す (下記参照)。
  - URL は独自パターン (`quick_select_patterns`) を既定より優先させている。
    既定の `scheme://\S+` は `(https://…)` の `)` や文末の `.` `,`、直後の日本語まで
    取り込むため。URL 内の対応した `(...)` は残す。パス / ハッシュ / UUID 等は既定の
    まま。
  - 制限: WezTerm は画面上の行単位で探すので、tmux pane 内で折り返された URL や
    隣の pane の文字と同じ行に並んだものはまとめて選べない (tmux 側の再描画で
    ソフト折り返し情報が失われるため)。
- `Ctrl+Arrow`: WezTerm 側では **あえてバインドしない**。デフォルトの CSI シーケン
  スをそのまま端末へ送り、tmux (prefix `C-f` のあと `C-Arrow`) で pane swap させる
  ため。
- タブ操作 (Windows): macOS の `Cmd+T` / `Cmd+W` / `Cmd+1..9` に合わせて、PC キーボード
  で Cmd の位置にある **`Alt`** に新規タブ / タブを閉じる / タブ切替を割り当てている
  (`Alt+9` は最後のタブ)。WezTerm 既定の `Ctrl+Shift+T` / `W` / `1..9` もそのまま使え
  る。Windows では Alt が Meta も兼ねるので、fish の `Alt+T` (transpose-words) と
  `Alt+W` (カーソル位置のコマンドの説明) はシェルに届かない (bash なら `Alt+T` と
  `Alt+1..9` の digit-argument)。

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

## 全画面 (macOS)

`Option+Enter` (WezTerm 既定の `ToggleFullScreen`) は macOS ネイティブ全画面
(`native_macos_fullscreen_mode = true`) にしている。

WezTerm 独自の全画面 (既定) は、ノッチを避ける上端の帯の高さを
`NSScreen.mainScreen` (キー入力を受けているウィンドウがある画面) の
`safeAreaInsets` から取る。しかもフォーカスが変わるたびに取り直し、行数は計算し
直さない (`window/src/os/macos/window.rs` の `get_os_parameters` と
`wezterm-gui/src/termwindow/mod.rs` の `focus_changed`)。そのため外部ディスプレイで
全画面にし、内蔵ディスプレイ上のアプリへ `Cmd+Tab` して戻ると、外部ディスプレイ側
にも内蔵のノッチ分 (20240203 版で 34px、約 1 行) の帯が入り、最下行が画面外に
はみ出していた。`Cmd+Tab` 先が外部ディスプレイ上のアプリなら起きず、`` Cmd+` `` で
WezTerm のウィンドウを一巡すると直る。

ネイティブ全画面はこの処理を通らず、ノッチは macOS が避ける。代わりに次の挙動に
なる:

- 全画面ウィンドウごとに Space ができ、出入りにアニメーションが入る。
- `` Cmd+` `` は今いる Space のウィンドウしか巡回しないので、同じディスプレイの別
  Space にある全画面ウィンドウには届かない (別ディスプレイで表示中の Space なら届く)。
  Space 切替の `Ctrl+←/→` も tmux 用に無効化している (上記) ので、接続先ごとに
  ウィンドウを分けず、1 つのウィンドウのタブ (`Cmd+T` / `Cmd+1..9` /
  `Cmd+Shift+[` `]`) で分ける。
- `Cmd+Tab` で戻った直後にカーソルが中抜きになるという報告がある
  ([wezterm#5315](https://github.com/wezterm/wezterm/issues/5315))。

nightly の `macos_fullscreen_extend_behind_notch = true` でも帯は消せるが採らない。
nightly 版 (`wezterm@nightly` cask。`wezterm` cask と conflict する) が要るうえ、
内蔵ディスプレイの全画面で最上行の中央 (tmux の中央寄せウィンドウ一覧) がノッチに
隠れる。
