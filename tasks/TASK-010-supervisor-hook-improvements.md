# TASK-010: permission-supervisor フックの改善（自動応答・scope 緩和・起動中トグル）

## 参照仕様

- User request on 2026-05-31: dot_claude の permission-supervisor フックを改善する。以下3点。
  1. ユーザーへの仕様の質問（`AskUserQuestion` 等）が自動 allow でスキップされてしまう。できるなら supervisor が代わりに答えるようにしたい。
  2. ユーザーが `repos/...` を「これ見て」と頼んでも、judge が「scope 外」として deny することがある。読み取りは許可されるべき。
  3. Claude Code を再起動せずに起動中で supervisor を有効/無効に切り替えたい。env 直値ではなく env で指定したファイルを毎回読む方式に変更する。
- TASK-008（supervisor フックの初版）
- AGENTS.md

## 調査メモ

- 既存フックは毎回新規プロセスで起動するため、env 直値（`CLAUDE_SUPERVISOR`）はセッション開始時に固定され、起動中に変更できない。一方ファイルは毎回読めるので、状態ファイルを読めばライブトグルできる。
- `AskUserQuestion` の `tool_input` には `questions[].options[]`（label/description）が含まれる → judge に選択肢を渡して回答させられる。
- PreToolUse フックが `permissionDecision:"deny"` + `permissionDecisionReason` を返すと、その reason がモデルへフィードバックされ、ツールはブロックされる。これを使い「supervisor が代理回答した」旨と回答内容をモデルに返す。
- ハード規則は always-allow より先に評価されるため、`Read` を広く許可しても秘密ファイル（`.env`/`.ssh`/`credentials` 等）は先にエスカレーションされる。秘密ファイルパターンを補強した上で `Read` を許可すれば「scope 外 deny」を直接解消できる。
- `logs/` は chezmoi 管理外（source に存在せず、target 実行時に生成）。状態ファイルの既定置き場として安全。

## 方針

- すべて既定オフ／後方互換。インストールしただけでは挙動を変えない。
- **(1) 自動応答**: `answer_user_questions`（既定 false）。有効時、`always_ask_tools` のツールを人間へ回す代わりに judge を answer モードで呼び、回答を deny の reason に載せてモデルへ返す。answer モードは backend が `context.mode=="answer"` で `prompt-answer-template.md` を使い `{"decision":"answer","answer":...}` を返す契約。回答不能なら従来どおり人間へ。
- **(2) scope 緩和**: プロンプトの deny 規則緩和（WIP 済）に加え、`Read` ツールと安全な read-only Bash を always-allow。秘密ファイルパターンを hard_escalate に追加して先に捕捉。
- **(3) 起動中トグル**: `CLAUDE_SUPERVISOR_STATE_FILE`（既定 `logs/state.json`）を毎回読み、config に重ねる。優先順位は env `CLAUDE_SUPERVISOR` > 状態ファイル > `supervisor.json`。`--on/--off/--toggle/--status` CLI で状態ファイルを更新し、実行中のセッションに即反映。

## チェックリスト

- [x] `task-010-supervisor-hook-improvements` ブランチを切る。
- [x] 状態ファイル方式（env でパス指定・config 重ね合わせ・CLI トグル）を実装する。
- [x] `Read`/read-only always-allow と秘密ファイルパターン補強を実装する。
- [x] answer モード（hook・codex/mock backend・answer テンプレート）を実装する。
- [x] supervisor.json / prompt / README を更新する。
- [x] `check-chezmoi-managed.sh` に新テンプレートを追加する。
- [x] オーケストレータ単体テスト（状態ファイルトグル・Read 許可・answer モード・後方互換）を通す。
- [x] `chezmoi managed` / `check-chezmoi-managed.sh` / `prek run --all-files` を通す。

## 完了条件

- [x] 起動中に `--on/--off` で supervisor をトグルでき、次のフック発火に即反映される。
- [x] `Read` 等の非秘密ファイル読み取りが scope 外で deny されない（秘密ファイルは従来どおりエスカレーション）。
- [x] `answer_user_questions` 有効時、`AskUserQuestion` に supervisor が代理回答し、無効時は従来どおり人間へ回る。
- [x] 既定オフで後方互換。検証スイートが通る。

## 作業ログ

- 2026-05-31: 作業開始。WIP（always_ask_tools・always_allow_patterns・rm ハード規則の精緻化・プロンプト緩和）を引き継ぎ、状態ファイル方式・answer モード・read 緩和を設計。
- 2026-05-31: 3点を実装。①状態ファイル（`CLAUDE_SUPERVISOR_STATE_FILE`／既定 `logs/state.json`）を毎回読み config に重ね、`--on/--off/--toggle/--status` CLI で起動中トグル。優先順位 env > state > json。②`Read`・安全な read-only Bash を always-allow に追加、秘密ファイルパターン（`.aws/`/`.netrc`/`secrets.*` 等）を hard_escalate に補強。③`answer_user_questions` で `AskUserQuestion` を judge が代理回答（answer モード backend＋`prompt-answer-template.md`、deny+理由でモデルへ返す）。`run_backend` を verdict dict 返却へリファクタ。`logs/` を `.gitignore`/`.chezmoiignore` で除外。単体テスト10件・codex 実機（fake）・`check-chezmoi-managed.sh`・`prek run --all-files` 全通過。
- 2026-05-31: 並行プロジェクトで独立トグルしたいとのフィードバックを受け、状態ファイルを **プロジェクト（git ルート）単位**に変更。既定を単一グローバル `logs/state.json` から `logs/state/<name>-<hash>.json`（cwd の git ルートをキーに正規化、サブディレクトリも同一リポジトリへ解決）へ。`CLAUDE_SUPERVISOR_STATE_FILE` 指定時はそのパスを verbatim 使用（複数セッション共有用）。`--list` を追加、`--status` に project 表示を追加。フック=イベント cwd／CLI=`os.getcwd()` で同一解決。per-project 5件＋回帰5件のテスト全通過、`prek` 全通過。
