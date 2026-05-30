# TASK-009: spec-setup を汎用 TDD 対応にし、subagent を別アカウントへ offload 起動できるようにする

## 参照仕様

- User request on 2026-05-30: 新規プロジェクトでも(言語・内容に依らず、開発的な TDD が使えるプロジェクトなら何でも) TDD ワークフローを使えるように `dot_claude/skills/spec-setup` のテンプレートを修正したい。あわせて、テンプレの subagent 起動方法を見直し、hooks 監督の要らない subagent 作業を別アカウント(A社)へ寄せて yumemi のトークン/クォータを節約したい。
- 参考実装(隣接プロジェクト):
  - `../compro-env/.claude/`(旧・commands 版): Rust / `cargo test` / 4層 DDD。`commands/spec-do.md` が RED(test-writer)→GREEN(implementer)→REFACTOR を回し、`agents/test-writer-prompt.md` / `agents/implementer-prompt.md` を Agent ツールで起動。
  - `../blog/.claude/`(新): TS / `pnpm test` + Playwright / src/lib→components→pages。`commands/spec-do.md` と `agents/test-writer.md` / `agents/implementer.md` で同パターン。
- AGENTS.md(chezmoi 規約、secret/host-specific 値の禁止)
- 既存: `dot_claude/skills/spec-setup/SKILL.md` と `templates/{spec-do,spec-review,spec-update}.md`(現状は逐次チェックリストのみで TDD subagent 非搭載)

## 調査メモ

- **両参考プロジェクトの subagent はステートレスなワーカー設計**。「タスク全文＋アーキ説明＋(GREEN には)test-writer の失敗テスト一覧」をプロンプトで丸ごと渡し、レポート(Status / 変更ファイル / テスト出力)を返させる。会話履歴を共有しない前提なので、起動方法を Agent ツール → headless 別プロセスに差し替えても構造が成立する。
- **アカウントの制約**: 1 つの `claude` プロセス = 1 アカウント。`Agent`/`Task` ツールの subagent は親プロセスのアカウント・settings・hooks を継承し、per-subagent のアカウント上書きは存在しない。よって「監督は yumemi、subagent だけ A社」を1セッション内で実現する唯一の道は、Agent ツールをやめて **Bash 経由で headless な別 claude を起動**すること。
  - 例: `CLAUDE_CONFIG_DIR=~/.claude-companyA claude -p --permission-mode acceptEdits --output-format json "<prompt>"`
  - headless は人間に承認を聞けないため `--permission-mode acceptEdits`(または allowlist)が必須。test-writer/implementer は元々無監督前提なので許容範囲。
  - 生成(高コスト)が A社 課金になり、yumemi はプロンプト生成＋レポート取り込みのみ → 狙い通りの節約。
- **A社 側制約**: org の managed-settings が hooks を無効化している(= dotfiles の permission supervisor は A社 では動かない)。`--dangerously-skip-permissions` 等も縛られる可能性があるため `acceptEdits` で足りるか要検証。
- **認証情報の分離(macOS)**: 当初は Keychain 単一エントリ(`Claude Code-credentials`)による衝突を懸念したが、**2026-05-30 の実機検証で衝突しないことを確認**。`~/.claude`(yumemi)と `~/.claude-companyA`(A社)が `CLAUDE_CONFIG_DIR` 切替で両方ログイン維持できた。→ CLAUDE_CONFIG_DIR 方式を採用。以下は当初の懸念メモ(参考): Keychain は単一エントリのため衝突しうる。Linux コンテナなら creds が平文 `~/.claude/.credentials.json` になり完全独立できる(Docker 案)が、toolchain をイメージに丸ごと入れる必要があり重い。→ **まず CLAUDE_CONFIG_DIR の実機検証を先行**し、衝突するなら Docker(または creds 平文保存の強制可否調査)へ。
- `supervisor` フックが有効(`CLAUDE_SUPERVISOR=1`)な場合、PreToolUse は subagent のツール呼びでも発火する。なお審査は codex(非 Claude)トークンを使うので、節約対象は subagent の Claude 生成トークン側。

## 方針(ユーザー確定済みの判断)

- **テンプレ設計**: offload(headless)主軸でテンプレ化する。`templates/spec-do.md` の RED/GREEN を、`CLAUDE_CONFIG_DIR=<alt> claude -p ...` の headless 起動を標準フローとして書く。
- **認証分離の検証**: まず `CLAUDE_CONFIG_DIR` 方式を実機検証(Keychain 単一エントリ衝突の有無)。ダメなら次手段(Docker / 平文 creds)を別途検討。
- **汎用化**: 言語・テストランナー・アーキ層をテンプレ変数化し、spec-setup 適用時にプロジェクト実態へ合わせて埋める(cargo/pnpm/その他、層名、検証コマンド)。subagent プロンプトも汎用ベース＋プロジェクト固有差分の形にする。
- chezmoi 規約遵守: secret / private URL / host-specific path / machine-local 値をテンプレや command に入れない。`CLAUDE_CONFIG_DIR` のパスやアカウント名はプレースホルダ/環境変数で表現。

## チェックリスト

### 認証分離の実機検証(先行)

- [x] `~/.claude-companyA` を作り `CLAUDE_CONFIG_DIR` 経由で A社 に `/login` する。
- [x] 通常 `~/.claude`(yumemi)を起動し、両アカウントがログイン維持できるか(Keychain 衝突の有無)を確認する。→ **衝突なし**。`claude auth status` で yumemi、`CLAUDE_CONFIG_DIR=$HOME/.claude-companyA claude auth status` で A社 が両方 `loggedIn:true` を維持(2026-05-30 実機確認)。
- [x] 衝突する場合の代替(creds 平文保存の強制可否 / Docker)を1つ特定し、結果を調査メモに追記する。→ 衝突しなかったため CLAUDE_CONFIG_DIR 方式を採用。Docker は不要(保険として温存)。
- [x] headless 起動の最小確認: `CLAUDE_CONFIG_DIR=~/.claude-companyA claude -p --permission-mode acceptEdits ...` が A社 で動くか、`acceptEdits` で file 編集まで通るかを確認する。→ **OK**。`/tmp/acc-test` で `hello.txt` 生成に成功(2026-05-30)。managed-settings は `acceptEdits` での編集を縛らないことを確認。

### spec-setup テンプレ汎用化(TDD + offload)

- [x] `task-009-tdd-spec-setup-account-offload` ブランチを切る。
- [x] `templates/spec-do.md` を RED→GREEN→REFACTOR の TDD サイクルに刷新。RED/GREEN は headless 別アカウント起動(`CLAUDE_CONFIG_DIR` + `claude -p` + `acceptEdits` + 構造化出力)を標準フローとして記述。
- [x] subagent プロンプトのテンプレを `templates/agents/test-writer.md` / `templates/agents/implementer.md`(汎用ベース)として追加。compro-env/blog の共通項(役割・YAGNI・レポート形式)を抽出し、言語/テスト/アーキはプレースホルダ化。
- [x] `SKILL.md` の手順を更新: 適用時にプロジェクトの言語・テストランナー・アーキ層・検証コマンド・offload 用 `CLAUDE_CONFIG_DIR` を確認して埋める旨を追記。
- [x] offload を使わない(同一アカウントで Agent ツール起動する)フォールバック手順もテンプレ内に明記。
- [x] `dot_codex/skills/` の symlink 整合(AGENTS.md 規約)を確認・更新する。→ `symlink_spec-setup` が spec-setup ディレクトリ全体を指すため新テンプレも自動包含。変更不要。

### 検証

- [x] `scripts/validate-skills.sh` 相当 / `chezmoi managed` / `scripts/check-chezmoi-managed.sh` / `prek run --all-files`(無ければ `pre-commit run --all-files`)を通す。→ 全通過。新テンプレ2件を `check-chezmoi-managed.sh` の require_managed に追加。
- [x] テンプレを未使用の新規ダミープロジェクト(任意言語)に spec-setup 適用 → spec-do で1サイクル(RED で失敗テスト→GREEN で通過)が回ることをドライランで確認する。→ `/tmp/spec-dryrun`(Python + stdlib unittest)で実施。RED: test-writer が `tests/test_calc.py` を生成し `ModuleNotFoundError` で正しく失敗。GREEN: implementer が `src/calc.py` を生成しテスト4件全通過。両フェーズとも offload(A社)経由で成立。**重要修正**: offload 起動には `acceptEdits` だけでなく `--allowedTools "Bash(<runner>:*)"` が必須(subagent はテスト実行が必要)。`bypassPermissions` は A社 の managed-settings で無効化され使えない(編集すら止まる)。テンプレに反映済み(`{{TEST_TOOL_ALLOW}}` 追加・`< /dev/null`・bypass 不使用の注意書き)。

## 完了条件

- [x] 言語・アーキに依らない汎用 TDD テンプレが spec-setup に入り、適用時にプロジェクト実態へ合わせて TDD サイクルを生成できる。
- [x] `templates/spec-do.md` の RED/GREEN が headless 別アカウント起動(offload)を標準フローとして記述し、同一アカウントのフォールバックも併記されている。
- [x] 認証分離(まず CLAUDE_CONFIG_DIR)の実機検証結果が調査メモに反映され、採用方式が決まっている。
- [x] secret / host-specific 値を含まず、chezmoi managed と skill validation、pre-commit 相当の検証が通っている。

## 作業ログ

- 2026-05-30: タスク作成。隣接プロジェクト compro-env(Rust/cargo)・blog(TS/pnpm+Playwright)の TDD subagent パターン(RED:test-writer / GREEN:implementer / REFACTOR、Agent ツール起動、ステートレス・ワーカー設計)を確認。アカウント制約(subagent は親アカウント継承・per-subagent 切替不可 → offload は headless `claude -p` + `CLAUDE_CONFIG_DIR` のみ)を整理。ユーザー判断で「offload 主軸テンプレ」「認証分離はまず CLAUDE_CONFIG_DIR を実機検証」に決定。
- 2026-05-30: 認証分離を実機検証。`claude auth status`=yumemi / `CLAUDE_CONFIG_DIR=$HOME/.claude-companyA claude auth status`=A社 が両方 `loggedIn:true` を維持し、Keychain 衝突なしを確認。CLAUDE_CONFIG_DIR 方式採用が確定。
- 2026-05-30: headless offload を実機検証。`/tmp/acc-test` で `env CLAUDE_CONFIG_DIR=$HOME/.claude-companyA claude -p --permission-mode acceptEdits "..."` を実行し `hello.txt` 生成に成功。A社 の managed-settings は `acceptEdits` での編集を縛らないことを確認。**検証フェーズ完了**。次はテンプレ汎用化(offload 主軸)に着手。
- 2026-05-30: テンプレ汎用化を実装。`templates/agents/test-writer.md`・`implementer.md`(汎用 + `{{...}}` プレースホルダ)を追加し、`templates/spec-do.md` を RED→GREEN→REFACTOR + offload 主軸起動(`CLAUDE_CONFIG_DIR=$CLAUDE_OFFLOAD_CONFIG_DIR claude -p --permission-mode acceptEdits`)に刷新。`SKILL.md` にコピー対象・プレースホルダ・起動方法を追記。`check-chezmoi-managed.sh` に新テンプレ2件を追加。validate-skills / chezmoi managed / check-chezmoi-managed / prek 全通過。残るはダミープロジェクトでのドライラン。
- 2026-05-30: ドライラン実施(`/tmp/spec-dryrun`, Python+unittest)。RED→GREEN が offload 経由で成立。判明した重要修正をテンプレへ反映: ①subagent はテスト実行が必要なため `acceptEdits` に加え `--allowedTools "Bash(<runner>:*)"`(新プレースホルダ `{{TEST_TOOL_ALLOW}}`)が必須 ②`bypassPermissions` は制限付き組織アカウントで無効化され使用不可 ③`< /dev/null` で stdin 待ち回避。再検証(validate-skills/chezmoi/prek)全通過。**全完了条件を満たし TASK 完了**。
