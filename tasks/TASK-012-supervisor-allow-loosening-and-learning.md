# TASK-012: permission-supervisor フックの改善（skills 許可・承認学習・許可緩和・scratch 書込/削除・ログ整理）

## 参照仕様

- User request on 2026-06-01: dot_claude の permission-supervisor フックを改善する。以下5点。
  1. **skills 内コマンドの常時許可** — skills のスクリプトは常に許可する。global の `allow` に入れ、supervisor もそれ相当を allow する（現状 `pr-review` スクリプト専用の `always_allow_pattern` を全 skills へ汎用化）。
  2. **承認の学習** — `ask` になって人間が allow した直前のツール呼び出しを記録し、supervisor が後から「似たコマンド」を自動許可する仕組み。
  3. **無効時はログを出さない** — `enabled=false` のとき `audit.jsonl` に `stage="disabled"` 行を書かない。あわせて監査ログ全体のノイズを減らす。
  4. **全体的に allow を緩める** — 通常の開発アクション（ビルド・テスト・パッケージ操作・`docker build` 等）が `ask` に回りすぎる。現に下記の監査ログで `docker build` が `ask`（理由「Docker build is a normal dev action but may perform network apt/package fetches and write Docker cache/images outside the project.」）。judge プロンプトと always-allow を緩めて過剰エスカレーションを減らす。
  5. **scratch ディレクトリの書込/削除許可** — `/tmp`・`$TMPDIR` に閉じた編集・`rm` は、通常ハード規則で必ず人間に回る再帰/強制削除であっても自動許可する。
- TASK-008（supervisor フック初版）／TASK-010（自動応答・scope 緩和・起動中トグル）
- 既存実装: `dot_claude/hooks/supervisor/executable_permission-supervisor.py` / `supervisor.json` / `prompt-template.md` / `README.md`
- `dot_claude/settings.json`（`permissions.allow` と PermissionRequest/PreToolUse フック登録）
- AGENTS.md（chezmoi ソースツリーの作法・`prek run --all-files`）

### 動機となった監査ログ（抜粋）

```json
{"...":"...","bash_description":"Rebuild with apt retry loop","decision":"ask","stage":"backend","reason":"Docker build is a normal dev action but may perform network apt/package fetches and write Docker cache/images outside the project.","elapsed_ms":17669}
```

## 調査メモ

- フックは毎回新規プロセスで、`PermissionRequest`（人間ダイアログ時）と `PreToolUse`（全呼び出し）に登録済み。`PostToolUse` は未登録。
- 評価順は `disabled → always_ask_tool → hard_rule → always_allow → backend(judge)`。`allow` は emit で許可短絡、`ask` は「出力なし＝人間へ」。
- **無効時ログ**: `main()` の `if not is_enabled(cfg): record.update(stage="disabled"); audit(record)` が毎回 1 行書いており、無効運用でも `audit.jsonl` が膨らむ（項目3の主因）。
- **skills 許可**: 現状 `always_allow_patterns` は `pr-review/scripts/*.py` 限定。`~/.claude/skills/<skill>/scripts/<script>.(py|sh)` 全般へ汎用化すれば良い。`settings.json` の `permissions.allow` に同等エントリを足せば supervisor オフの対話運用でもプロンプトが出ない（フックの allow と二重化されるが両者は独立に効く）。
  - 補足: `settings.json` 側で allow 済みでも `PreToolUse` フックは発火するため、supervisor 有効時は別途フック側でも許可しないと judge へ回ってしまう。よって supervisor 内のパターン許可は必須。
- **承認学習**: 人間の許可結果はフックに直接は返らない。ただし `PostToolUse` は **ツールが実際に実行された後**にのみ発火する＝supervisor が `ask`（出力なし）にした呼び出しが PostToolUse まで到達したら「人間が allow した」と判定できる。
  - 仕組み: `PreToolUse`/`PermissionRequest` で `stage=="backend"` かつ `decision=="ask"` のとき、`tool_use_id` をキーに正規化シグネチャを **pending ストア**へ記録 → `PostToolUse` で同じ `tool_use_id` の pending を見つけたら **学習 allowlist** へ昇格。`hard_rule`・`always_ask_tool`・`disabled` は学習対象外。
  - 正規化シグネチャ（推奨どおり）: Bash は単一の単純コマンドに限り、`argv[0]`（＋ `git`/`gh`/`cargo`/`npm`/`docker`/`mise` 等のサブコマンド `argv[1]`）を骨格にし、残り引数は `<args>` にテンプレ化（例 `git log --oneline -20` → `git log <args>`）。シェルメタ文字・グロブ/チルダを含む場合は学習しない。
  - 安全: 昇格時にも `hard_escalate_patterns` を再チェックし、一致するシグネチャは決して学習しない。学習は `hard_rule` を上書きできない（評価順は `hard_rule` が先）。
- **過剰エスカレーション**: `prompt-template.md` の決定規則が「writes/side effects outside the project → ask」と広く、`docker build`（Docker キャッシュ/イメージを cwd 外に書く）など**ローカル開発の通常副作用**まで `ask` に倒している。「ローカル開発の副作用（ビルドキャッシュ/依存導入/`docker build`/コンテナのローカル実行）は通常 allow、`ask`/`deny` は不可逆なデータ損失・秘密の読み書き/持ち出し・外部公開（push/deploy/publish）に限る」へ緩める。
- **scratch 書込/削除**: `rm -r`/`-f` はハード規則で必ず人間へ。`/tmp`・`$TMPDIR` に**完全に閉じた**操作だけは自動許可したい。シンボリックリンクや `..` で scratch 外へ抜けられないよう、各オペランドを `realpath` 解決して scratch ルート配下に厳密包含されることを要求する必要がある。macOS の `$TMPDIR` は `/private/var/folders/...` 実体（`/var` は `/private/var` へのシンボリックリンク）なので realpath 正規化が必須。

## 方針

- TASK-010 同様、**既定は後方互換・新挙動は明示オプトイン**。supervisor 自体が有効なときのみ各機能が働く。学習・scratch 許可は config/CLI で個別にトグル可能にし、既定値は安全側に倒す。
- ハード規則（`sudo`/`curl|sh`/秘密ファイル/`mkfs`/`dd` 等）は**一切緩めない**。scratch 削除のみ、`rm` 再帰/強制のハード規則に対する限定的な事前許可として扱う。

### (1) skills 内コマンドの常時許可

- `always_allow_patterns` に汎用パターンを追加（`pr-review` 専用パターンは内包されるので置換も可、当面は両立で可）:
  ```
  ^\s*(python3|bash|sh)\s+(~|/Users/[^/\s]+|/home/[^/\s]+)/\.claude/skills/[\w-]+/scripts/[\w-]+\.(py|sh)\b
  ```
  既存 allow と同じく「単一の単純コマンド（メタ文字なし）」前提。スクリプトパスは固定なので `~` 可。
- `settings.json` の `permissions.allow` に対話運用向けエントリを追加:
  ```
  Bash(python3 ~/.claude/skills/*/scripts/*:*)
  Bash(bash ~/.claude/skills/*/scripts/*:*)
  ```

### (2) 承認の学習（ask → 人間 allow → 後から自動許可）

- `settings.json` に `PostToolUse`（matcher `*`）で同スクリプトを登録。
- 学習トグル `learn_from_approvals`（既定 **false**）と CLI `--learn-on/--learn-off`、確認用 `--list-learned`、破棄用 `--forget-learned [sig|--all]`。
- ストア（いずれも `logs/` 配下・chezmoi 管理外・プロジェクト単位）:
  - pending: `logs/learned/pending/<proj>-<hash>.json`（`tool_use_id → {sig, ts, session_id}`、書込時に古い項目を時間で間引き）。
  - 学習済み: `logs/learned/<proj>-<hash>.json`（`{"signatures":[{"sig","approved_ts","count"}]}`）。
- フロー: `PreToolUse/PermissionRequest` で `stage=="backend" && decision=="ask"` のとき pending へ記録 → `PostToolUse` で一致 pending があれば（再度ハード規則チェックを通過した場合のみ）学習済みへ昇格・`count++`。
- `matches_allow_rule` に学習済みシグネチャ照合を追加（評価順は `hard_rule` の後＝危険系は学習で覆らない）。
- 正規化シグネチャ関数 `command_signature(tool_name, tool_input)` を実装（上記「調査メモ」の規則）。当面は Bash の単一単純コマンドのみ対象。非 Bash ツールはスコープ外（将来拡張余地として注記）。

### (3) 無効時はログを出さない・ログ整理

- `main()` の無効分岐から `audit(record)` を削除し、何も書かず return。
- ノイズ低減: `log_decisions`（既定 `["allow","deny","answer"]`、＝ `ask` は記録しない）を config 化、もしくは最小実装として「`ask` のうち `stage in {always_ask_tool}` は記録しない」。実装時にどちらかへ寄せる（既定で `disabled`/`always_ask_tool` を残さない方針）。

### (4) 全体的に allow を緩める（過剰エスカレーション抑制）

- `prompt-template.md` の決定規則を緩和:
  - allow に「ローカル開発の通常副作用（ビルド・テスト・lint・パッケージ/依存導入・`docker build`・ローカルコンテナ実行・ビルドキャッシュ書込）」を明記。
  - 「out of project / ローカル副作用」だけを理由に `ask` にしない。`ask`/`deny` は**不可逆なデータ損失・秘密の読み書き/持ち出し・外部公開（push/deploy/publish/レジストリ push）**に限る旨へ書き換え。
- 補完として `always_allow_patterns` に頻出の非破壊コマンド（例: `cargo build|test|check|clippy`, `npm|pnpm run ...`, `pytest`, `go build|test`, `docker build`）を必要に応じ追加検討（ただし副作用ありコマンドは judge 緩和を主軸にし、パターン追加は単一単純コマンドに限る）。
- (2) の学習と相乗で繰り返しの `ask` を削減。

### (5) scratch ディレクトリの書込/削除許可

- config `scratch_dirs`（既定 `["/tmp"]`）＋ 実行時 `$TMPDIR` を自動追加。各ルートは `realpath` 正規化。
- `matches_scratch_allow(cfg, tool_name, tool_input)` を **hard_rule より前**に評価（scratch に閉じた `rm` を許可するため）。一致条件は厳格に:
  - `Edit`/`Write`/`NotebookEdit`: 対象 `file_path` を `realpath` 解決し、いずれかの scratch ルート**配下**（ルート自身は不可）なら許可。
  - `Bash`: 単一の単純コマンド（`_BASH_UNSAFE_CHARS` を含めば不可）かつ動詞が許可集合 `{rm, mv, cp, mkdir, rmdir, touch}` のみ。`shlex` で分解し、**全オペランド**（非フラグ引数）を `cwd` 基準で `realpath` 解決して scratch 配下に厳密包含、`..` によるルート脱出・ルート自身の指定・グロブ（`*?~[]`）を拒否。少なくとも1つのパス引数が必要。
  - シンボリックリンクは `realpath` で実体解決した上で包含判定（scratch 内リンクが外を指す場合は拒否）。
- scratch 一致時は allow を emit し、`stage="scratch_allow"` で監査（学習対象外）。それ以外は従来どおり hard_rule → judge へ。
- （任意）`settings.json` に `Edit(/tmp/**)` 等の allow を足すかは要検討（パスのチルダ/絶対 glob 構文の確認後に判断）。

## チェックリスト

- [x] `task-012-supervisor-allow-loosening-and-learning` ブランチを切る。
- [x] (1) `always_allow_patterns` の skills 汎用化＋`settings.json` allow 追加。
- [x] (3) 無効時ログ抑止＋ログノイズ低減（`log_decisions` 既定 `["allow","deny","answer"]`）。
- [x] (4) `prompt-template.md` の決定規則緩和（ローカル副作用は allow）。
- [x] (5) `scratch_dirs` ＋ `matches_scratch_allow`（Edit/Write/Bash、realpath 厳密包含、hard_rule 前評価）。
- [x] (2) `PostToolUse` 登録、pending/学習ストア、正規化シグネチャ、`matches_allow_rule` 照合、`learn_from_approvals` トグルと `--learn-on/--learn-off/--list-learned/--forget-learned` CLI。
- [x] `supervisor.json` / `README.md` を全項目に合わせて更新。
- [x] `scripts/check-chezmoi-managed.sh` は対象ファイル増減なし（スクリプト群は既存）を確認。
- [x] オーケストレータ単体テスト（skills 汎用許可・学習の pending→昇格・正規化照合・scratch 許可/拒否境界・無効時ログ無し・log_decisions・後方互換）34件を ephemeral に通す。
- [x] `scripts/check-chezmoi-managed.sh` / `prek run --all-files` を通す。

## 完了条件

- [x] 任意 skill の `scripts/*.(py|sh)` 実行が supervisor 有効時に自動許可され、対話運用でもプロンプトが出ない。
- [x] `learn_from_approvals` 有効時、`ask`→人間 allow した Bash コマンドの正規化シグネチャが学習され、以後の同系統コマンドが自動許可される。`hard_escalate` 一致系は決して学習されない。`--list-learned/--forget-learned` で確認・破棄できる。
- [x] supervisor 無効時に `audit.jsonl` へ行を書かない。有効時も `ask`/`disabled` の冗長行が出ない。
- [x] `docker build` 等のローカル開発アクションが judge プロンプト上 allow される（秘密の読み書き・外部公開・不可逆破壊は従来どおり `ask`/`deny`）。
- [x] `/tmp`・`$TMPDIR` 配下に閉じた編集・`rm -rf` が自動許可され、scratch 外へ `..`/シンボリックリンクで抜ける指定や scratch 外パスを含む削除は従来どおり人間へエスカレーションされる。
- [x] 既定オフで後方互換。検証スイートが通る。

## 作業ログ

- 2026-06-01: 要件整理とタスク化。User から hook 改善5点（skills 常時許可・承認学習・無効時ログ抑止＋ノイズ低減・全体的な allow 緩和・scratch 書込/削除許可）。設計判断は AskUserQuestion で確定（skills=パターン汎用化＋settings allow、学習=正規化シグネチャ・プロジェクト単位・自動昇格・要確認可・hard_rule は非学習）。`docker build` が `ask` に回る監査ログを動機に、judge プロンプト緩和とローカル副作用 allow を方針化。scratch は realpath 厳密包含でハード規則 `rm` の限定事前許可として設計。
- 2026-06-01: 5点を実装。①`always_allow_patterns` を全 skills スクリプト（`python3`/`bash`/`sh` × `skills/*/scripts/*.(py|sh)`）へ汎用化、`settings.json` の `permissions.allow` にも追加。②`PostToolUse` フックを登録し、backend `ask`→人間 allow→実行（PostToolUse 到達）で正規化シグネチャ（`argv[0]`＋サブコマンド、引数破棄）を `logs/learned/<proj>.json` へ昇格。pending は `logs/learned/pending/`（TTL 1h）。昇格時ハード規則再チェック。`learn_from_approvals`（既定 false）＋`--learn-on/off`/`--list-learned`/`--forget-learned` CLI、`--status` に件数表示。③無効時は無出力・無ログ化、`log_decisions`（既定 `["allow","deny","answer"]`）で `ask` を既定非記録。④`prompt-template.md` を緩和（ビルド/テスト/依存導入/`docker build`/ローカルコンテナは allow、`ask`/`deny` は不可逆損失・秘密・外部公開に限定）。⑤`scratch_dirs`（既定 `/tmp`＋`$TMPDIR`）に realpath 厳密包含される `Edit`/`Write`/`NotebookEdit` と `{rm,mv,cp,mkdir,rmdir,touch}` 単一単純コマンドを hard_rule より前に許可。`..`/シンボリックリンク脱出・ルート自身・scratch 外パスは拒否。ephemeral 単体テスト34件（chezmoi 同様に `executable_` 接頭辞を剥がした一時コピーで実行）全通過、`check-chezmoi-managed.sh`・`prek run --all-files` 全通過。テストはリポジトリ慣例に従い未コミット。
