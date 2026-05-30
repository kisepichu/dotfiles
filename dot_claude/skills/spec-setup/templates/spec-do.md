仕様からタスクファイルを生成し、実装または作業を開始する。

## 引数

- 機能名、コマンド名、または作業名を受け取る。
- 引数がなければ「どの仕様を進めますか?」と聞く。

## 手順

1. 対象仕様を探す。
   - `docs/features/{name}.md`
   - `docs/commands/{name}.md`
   - `docs/{name}.md`
   - `docs/spec.md` の該当箇所
2. `CLAUDE.md` または `AGENTS.md` があれば、プロジェクトルールを読む。
3. 仕様をタスクに分解する。
   - 開発プロジェクトではレイヤー、モジュール、UI/テスト単位に分ける。
   - 非開発プロジェクトでは調査、判断、作成、検証、公開のように成果物単位に分ける。
4. `tasks/doing/TASK-NNN-{name}.md` を作る。
   - NNN は `tasks/todo/`, `tasks/doing/`, `tasks/done/` の最大番号 + 1。
   - `tasks/doing/` がなければ作成する。
5. ブランチ名をユーザーに確認し、メインブランチから feature ブランチを切る。
6. チェックリストを上から進める。
   - **テストのある開発プロジェクトなら、各項目を下の「TDD サイクル」で進める。**
   - test を書けない非実装作業なら、各チェック項目の成果物と検証方法を明記して進める。
   - 完了した項目はその都度 `[x]` に更新する。
7. 完了時は検証結果を記録し、必要なら `tasks/done/` に移動する。
   - 仕上げに検証コマンド一式を通す: {{VERIFY_COMMANDS}}
     <!-- 例: cargo fmt --all / cargo clippy --workspace / cargo test --workspace
              pnpm astro check / pnpm lint / pnpm test / pnpm build -->

## TDD サイクル (チェックリスト項目ごと)

各項目を **RED → GREEN → REFACTOR** で進める。RED が GREEN まで完了してから次の項目へ。

- **RED** — `.claude/agents/test-writer.md` のテンプレを task 全文で埋め、test-writer を起動。
  失敗テストが「未実装による失敗」であることを確認してから次へ。
- **GREEN** — `.claude/agents/implementer.md` のテンプレを埋め、**test-writer の失敗テスト名・
  ファイルパスをプロンプトに含めて** implementer を起動。全テスト通過のレポートを得る。
- **REFACTOR** — 全テストが通る状態を保ったまま、オーケストレータ自身が整理する。

### subagent の起動方法 (offload 主軸)

test-writer / implementer は **無監督で回せる定型ワーカー**なので、コスト節約のため
**別アカウントの headless claude** に逃がすのを既定とする。生成コストは offload 先に課金され、
オーケストレータは「プロンプト生成 + レポート取り込み」だけを負担する。

1. 埋めたプロンプトを一時ファイルに書く (例: `tasks/.agent-prompt.md`)。
2. プロジェクトルートを cwd にして起動する:

   ```sh
   env CLAUDE_CONFIG_DIR="$CLAUDE_OFFLOAD_CONFIG_DIR" \
     claude -p "$(cat tasks/.agent-prompt.md)" \
     --permission-mode acceptEdits \
     --allowedTools "{{TEST_TOOL_ALLOW}}" \
     --output-format text < /dev/null
   ```

   - `$CLAUDE_OFFLOAD_CONFIG_DIR` は offload 先アカウントの config ディレクトリ
     (例: 各自の `~/.claude-<sub>`)。値は環境変数で渡し、command にハードコードしない。
   - `--permission-mode acceptEdits` で headless でも**編集**が通る (人間に承認を聞けないため必須)。
   - **`--allowedTools` でテスト実行コマンドを明示許可する**: `{{TEST_TOOL_ALLOW}}`
     (例: `Bash(cargo:*)` / `Bash(pnpm:*)` / `Bash(python3:*)`)。これが無いと
     subagent はテストを実行できず RED の失敗確認も GREEN の通過確認もできない。
   - `< /dev/null` で stdin 待ちの警告を避ける。
   - subagent はこの cwd の作業ツリーを直接編集する。編集結果はそのまま repo に残る。
3. stdout のレポート (Status / 変更ファイル / テスト出力) を読み、RED は失敗確認、
   GREEN は全通過を確認する。オーケストレータ自身でもテストを再実行して裏取りしてよい。

> **注意 — `--dangerously-skip-permissions` / `bypassPermissions` は使わない**。
> 制限付き組織アカウント(managed-settings)ではこのモードが無効化されており、
> 逆に何も自動許可されなくなる(編集すら止まる)ことを実機で確認済み。
> 必要十分なのは `acceptEdits` + `--allowedTools` の組み合わせ。

> **フォールバック**: `$CLAUDE_OFFLOAD_CONFIG_DIR` が未設定なら、同じプロンプトで
> Agent (Task) ツールの general-purpose subagent を**そのセッション内**で起動する。
> この場合は現在のアカウントで生成され、hooks が有効なら監督対象になる。

## タスクファイル形式

```markdown
# TASK-{NNN}: {name}

## 参照仕様

- docs/...

## チェックリスト

- [ ] ...

## 完了条件

- [ ] ...

## 作業ログ

- YYYY-MM-DD: 作業開始
```

## 注意

- 仕様に曖昧さがあり、合理的な仮定では危険な場合だけユーザーに確認する。
- 既存のタスクファイルがある場合は重複作成せず、続きから進める。
- RED で test を書く前に実装を書かない。GREEN まで終える前に次の項目へ進まない。
- 一時プロンプトファイル (`tasks/.agent-prompt.md` 等) は `.gitignore` 済みにするか、
  commit に含めないこと。
