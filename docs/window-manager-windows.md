# ウィンドウマネージャ (Windows / GlazeWM)

Windows ホストでは [GlazeWM](https://github.com/glzr-io/glazewm) で
`docs/superpowers/specs/2026-11-21-window-manager-design.md` のキー配置を使う。
`Mod` は `Win`。

## 配置

設定は `dot_glzr/glazewm/` にある。chezmoi は Windows ネイティブ以外ではこの
ディレクトリを無視する (`.chezmoiignore`)。WSL で `chezmoi apply` すると、
`run_onchange_after_36-install-windows-glazewm-config.sh.tmpl` が次の 4 ファイルを
`%USERPROFILE%\.glzr\glazewm\` にコピーし、動いている GlazeWM に設定を再読み込み
させる。4 ファイルのどれかが変わったときだけ再実行される。

- `config.yaml`: GlazeWM の設定
- `window-picker.ahk`: `Win+Space` のウィンドウピッカー (AutoHotkey v2)
- `window-picker-lib.ahk`: ピッカーの JSON 解析と絞り込み。テストは
  `scripts/test-glazewm-window-picker.sh` (prek のフックとして実行される)
- `win-key-mask.ahk`: `Win` を使った操作のあとに Start メニューが開くのを防ぐ
  (下記「Win キーと Start メニュー」)。GlazeWM の `startup_commands` で起動し、
  GlazeWM が終了すると自分も終了する

Windows 側のコピーを直接編集しても、次のコピーで上書きされる。変更は repo 側で
行う。ワークスペースとディスプレイの割り当ては再読み込みだけでは組み直されない
ので、`workspaces` を変えたときは GlazeWM を再起動する (下記「終了と再起動」)。
再起動すると `startup_commands` で Brave と WezTerm の窓がもう 1 つずつ開く。

## 初回セットアップ

一度だけ行う。スクリプトは、手順 1〜3 が済んでいないと警告とコマンドを表示する。

1. GlazeWM を入れる。Zebar は入れない。UAC の確認が 1 回出る。

   ```
   winget install --id glzr-io.glazewm --exact --override "/quiet /norestart Custom_InstallZebar=0"
   ```

2. AutoHotkey v2 を入れる。

   ```
   winget install --id AutoHotkey.AutoHotkey --exact
   ```

3. `Win+L` を GlazeWM に渡すため、画面ロックを無効にする。管理者のターミナルで
   実行する。WSL から起動したプロセスは中整合性レベルで動き、`Policies` キーには
   読み取り権限しかないので、スクリプトからは書けない。

   ```
   reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f
   ```

   `Win+L` だけでなく Ctrl+Alt+Del 画面の「ロック」も使えなくなる。
4. WSL で `chezmoi apply` する。
5. GlazeWM のトレイアイコンを右クリックし、「Run on system startup」にチェックを
   入れる。
6. ほかのタイル型ウィンドウマネージャと窓の自動配置を止める。PowerToys の
   FancyZones は無効にする。komorebi などがスタートアップに登録されていれば外す。

## キー

| キー | 動作 |
|---|---|
| `Win+1`〜`9` | ワークスペース N へ移動。表示中の番号をもう一度押すと直前のワークスペースに戻る |
| `Win+0` | 縦置きディスプレイのワークスペース 0 へ移動 (Windows だけ) |
| `Win+Shift+1`〜`9`, `Win+Shift+0` | 窓をワークスペース N へ送り、一緒に移動する |
| `Win+H/J/K/L` | 左/下/上/右の窓へフォーカス |
| `Win+Shift+H/J/K/L` | 窓を左/下/上/右へ動かす |
| `Win+F` | 全画面の切り替え |
| `Win+Shift+Space` | フローティングの切り替え |
| `Win+-` / `Win+=` | 幅を 5% 狭く / 広く |
| `Win+Space` | ウィンドウピッカー |

GlazeWM が使う `Win+…` は、同じキーの Windows 標準の動作 (タスクバーの
`Win+数字`、拡大鏡の `Win+-`/`Win+=`、音声入力の `Win+H` など) より優先される。

入力言語 (ENG / JPN) の切り替えは `Win+Space` から **`Win+Ctrl+Space`** に移す。
GlazeWM はバインドにない修飾キー (ここでは Ctrl) が一緒に押されているとキーを
素通しするので、`Win+Ctrl+Space` は Windows に届く。左 `Alt+Shift` でも切り替え
られる。

### Win キーと Start メニュー

Windows は、`Win` を押してから離すまでにほかのキーが届かないと Start メニューを
開く。GlazeWM は `Win+2` の `2` のように、バインドしたキーを Windows に渡さない
ので、短く押すと Start が開くことがある
([glazewm#1215](https://github.com/glzr-io/glazewm/issues/1215))。最初の確認では
再現しなかったが、使っているうちに `Win+数字` と `Win+Space` のあとに Start が
開くようになった。`Win+Space` では Start にフォーカスを取られてピッカーを操作
できなくなった。

そのため `win-key-mask.ahk` が、`Win` を押した瞬間に未割り当てのキー (`vkE8`) を
送る (`~LWin::Send("{Blind}{vkE8}")`)。Windows からは毎回「`Win` を使う組み合わせ
だった」と見えるので、Start は開かない。副作用として `Win` を単独で押しても Start
は開かない。Start は `Ctrl+Esc` かタスクバーの Start ボタンで開く。

ピッカーは、ほかの窓 (Start を含む) にフォーカスが移ると 0.25 秒以内に閉じる。

## ワークスペースとディスプレイ

GlazeWM はディスプレイに左から 0, 1, … と番号を付ける。この PC では左の縦置きが
0、メインが 1 になる。

- ワークスペース 1〜9 はメインに固定する (`bind_to_monitor: 1`)。
- ワークスペース 0 は縦置きに固定する (`bind_to_monitor: 0`)。`Win+0` で移動し、
  `Win+Shift+0` で窓を送る。
- ディスプレイが 1 枚のときは割り当てが無視され、すべてそのディスプレイに開く。
  ディスプレイの並びを変えたら番号を見直す。

画面の電源を切ると、モニターによっては Windows から「取り外された」ように見える。
GlazeWM はそのディスプレイのワークスペースを残ったディスプレイへ移し、電源が
戻ると固定先のワークスペースを元のディスプレイへ戻す。固定 (`bind_to_monitor`)
が無いと戻らない。また、空いているワークスペースの定義が無いと
`No workspace config available to activate workspace` になる。

## アプリの固定 (slot)

| slot | アプリ | ルール (`window_rules`) |
|---|---|---|
| 1 | ゲーム (VRChat, Overwatch, Street Fighter 6) | `move --workspace 1`, `set-fullscreen` |
| 2 | Brave | `move --workspace 2` |
| 3 | WezTerm | `set-tiling`, `move --workspace 3` |
| 4〜9 | 空き。そのとき開いた窓を置く | なし |

- ルールは窓ごとに一度だけ動く。あとは `Win+Shift+N` で自由に動かせる。
- Brave の PWA (Discord のショートカットなど) も `brave.exe` なので slot 2 に入る。
- WezTerm は `window_decorations = "RESIZE"` のせいで GlazeWM から「サイズを変え
  られない窓」に見え、そのままだとフローティングになる。`set-tiling` でタイル
  表示に戻している。
- ゲームはボーダーレスウィンドウで動かし、GlazeWM の管理下で全画面にする。
  `ignore` にするとワークスペースの木から外れ、`Win+1` が空のワークスペースを
  開くことになる。

### ゲームを足す

1. ゲームを起動し、WSL で実行ファイル名を調べる。

   ```bash
   '/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe' query windows | jq -r '.data.windows[] | "\(.processName)\t\(.title)"'
   ```

   タスクマネージャーの「詳細」タブに出る名前から `.exe` を除いたものでもよい。
2. `dot_glzr/glazewm/config.yaml` の slot 1 のルールに 1 行足す。

   ```yaml
         - window_process: { equals: 'NewGame' }
   ```

3. `chezmoi apply` する。すでに開いている窓にはルールが効かないので、ゲームを
   起動し直す。

## ウィンドウピッカー (`Win+Space`)

すべてのワークスペースの窓を一覧にして、選んだ窓とそのワークスペースを表示する。

- 入力すると絞り込む。空白で区切った語がすべて「ワークスペース番号 アプリ名
  タイトル」に順番どおり含まれる窓が残る (飛び飛びでもよい)。連続して一致する
  窓ほど上に出る。
- `↑` / `↓` で選び、`Enter` かダブルクリックで移動する。`Esc` を押すか、ほかの
  窓をクリックすると閉じる。
- ブラウザのタブは窓ではないので、ブラウザのタブ検索を使う。

PowerToys Command Palette の「Switch windows」は使えない。GlazeWM は隠した
ワークスペースの窓を cloak する (`DWMWA_CLOAKED = 2`)。Command Palette の Window
Walker は、別の仮想デスクトップにある窓を除き、cloak された窓を一覧から外す
(`OpenWindows.cs`)。そのため、`glazewm query workspaces` の結果を AutoHotkey の
GUI に並べ、選んだ窓に `glazewm command focus --container-id <id>` を実行している。
GlazeWM 3.10.1 のこのコマンドはフォーカスを移すだけで、隠れたワークスペースを
表示し直さない (窓は cloak されたまま、画面も切り替わらない)。そのため、窓の
ワークスペースが隠れているときは先に `focus --workspace N` で表示する。表示中の
ワークスペースには送らない。`toggle_workspace_on_refocus` で直前のワークスペースに
戻ってしまうため。

## 終了と再起動

`glazewm.exe` は manifest で `uiAccess="true"` を指定しているので、通常の権限の
シェル (WSL を含む) からは `taskkill` できない。

- 終了: トレイアイコンの Exit、または WSL から
  `'/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe' command wm-exit`。
  隠れたワークスペースの窓を表示に戻してから終わる。
- 起動: スタートメニューの GlazeWM、または WSL から
  `cmd.exe /c start "" "C:\Program Files\glzr.io\GlazeWM\glazewm.exe"`。
- インストーラの最後に自動で起動したものも同じく通常の権限からは止められない。

### 応答しなくなったとき

キーにも `glazewm` の CLI にも反応しない (CLI は GlazeWM を待ち続けて戻らない)
ときは、管理者のターミナルで GlazeWM と見張り役の `glazewm-watcher` をまとめて
終了させる。

```
taskkill /F /IM glazewm.exe /IM glazewm-watcher.exe
```

`glazewm-watcher` が残ると GlazeWM の IPC ポート (127.0.0.1:6123) を握ったままに
なり、次の起動が `Only one usage of each socket address` (os error 10048) で失敗
する。

強制終了すると、隠れたワークスペースにあった窓が cloak されたまま見えなくなる
ことがある。GlazeWM を起動し直しても、cloak された窓は「見えない窓」として扱われ
拾われない。タスクマネージャーでそのアプリを終了して開き直すか、サインインし
直すと戻る。

### スリープ復帰後にキーが効かないとき

スリープから復帰したあと、`Ctrl` が押されたままの扱いになり、数字が入らない、
`f` `l` で tmux のペインが動く、ということが一度あった。OS のキー状態
(`GetAsyncKeyState`) では離されていたので、キーを自前で追跡しているソフト
(WezTerm、PowerToys Keyboard Manager、AutoHotkey、GlazeWM のどれか) が離した
イベントを取りこぼしていた。GlazeWM を入れる前から起きていたかは分からない。

左右の `Ctrl` (と `Shift`、`Alt`) を一度ずつ押して離す。WSL から AutoHotkey で
`Send("{LCtrl up}{RCtrl up}{LShift up}{RShift up}{LAlt up}{RAlt up}")` を実行して
も戻る (このときはこれで戻した)。

## GlazeWM 3.10.1 の注意点

- `shell-exec` のプログラムのパスを `"` で囲むと失敗する
  (`command doesn't have an ending "`)。パスは囲まずに書く。スペースを含んでいても、
  GlazeWM が単語を 1 つずつ足しながら実在するファイルを探す。引数は囲んでよい。
- tmux の `C-f M-1`〜`M-5` (レイアウト切り替え) は、WezTerm が `Alt+数字` を
  タブ切り替えに使うので届かない。`C-f Space` を使う。
