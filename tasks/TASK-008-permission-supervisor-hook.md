# TASK-008: Claude Code の承認を別AI（codex 等）で自動審査する supervisor フック

## 参照仕様

- User request on 2026-05-30: Claude Code の approve を AI で自動化したい。agent が許可を求めたとき、人間が内容・意図の妥当性・危険度を見て許可/拒否/別指示していた判断を、別の AI（codex など）に肩代わりさせる supervisor 的仕組み。PermissionRequest フックでスクリプトを起動し、その中で codex を動かす案。dot_claude 内に作る。
- AGENTS.md
- 計画ファイル: `~/.claude/plans/fluffy-munching-pascal.md`

## 調査メモ

- Claude Code には `PermissionRequest`（人間に許可ダイアログが出る瞬間だけ発火）と `PreToolUse`（全ツール呼び出しで発火、`-p` 非対話でも動作）の2フックがある。前者がユーザーの「approve が求められたとき」に最も一致。
- フックは stdin で `tool_name`/`tool_input`/`cwd`/`session_id`/`hook_event_name` の JSON を受け取り、stdout に JSON を返して allow/deny を制御。**何も出力しなければ従来どおり人間に委ねられる**（＝最も堅牢な「エスカレーション=ask」表現）。
- フック内から子プロセス（`codex exec`）を同期起動可能（デフォルトタイムアウト600秒）。会話履歴全文はフックに渡らないため、審査 AI が見られるのはツール情報＋cwd に限られる。
- `~/.claude/settings.json` は既存で `{"theme":"dark"}` のみ。管理化時は theme を保持して hooks を追記。
- 環境: macOS の system `python3` は 3.9 で `tomllib` 無し → 設定は JSON（`supervisor.json`）にした。chezmoi 実行ビットは `executable_` 接頭辞。`codex` は v0.135.0 で `codex exec` 利用可。

## 方針

- スコープはグローバル（`dot_claude`→`~/.claude`）＋**明示オプトイン**（`enabled:false` 既定。`CLAUDE_SUPERVISOR=1` または config で有効化）。インストールしただけでは何も自動承認しない。
- フックは `PermissionRequest`（主）＋ `PreToolUse`（フォールバック）の両方に同一オーケストレータを登録。
- 審査バックエンドは差し替え可能に抽象化。既定は `codex exec`（`judge-codex.sh`）、テスト用に `judge-mock.sh`。
- 多層防御で fail-open を排除: ①オプトイン ②ハード規則（危険カテゴリは AI が allow でも必ず人間へ）③不確実/タイムアウト/エラーは一律 ask（人間へ）④監査ログ `logs/audit.jsonl`。

## チェックリスト

- [x] フック機能・スキーマ・制約を調査する。
- [x] `task-008-permission-supervisor-hook` ブランチを切る。
- [x] `dot_claude/hooks/supervisor/` にオーケストレータ・codex/mock バックエンド・設定・プロンプト・README を作成する。
- [x] `dot_claude/settings.json`（theme 保持＋両フック登録）を作成する。
- [x] `scripts/check-chezmoi-managed.sh` に新 managed パスを追加する。
- [x] オーケストレータ単体テスト（disabled/ハード規則/allow/deny/timeout/非0/不正JSON）を通す。
- [x] codex バックエンド実機テスト（安全例=allow / 範囲外書込=deny）を通す。
- [x] `validate-skills.sh` / `chezmoi managed` / `check-chezmoi-managed.sh` / `prek run --all-files` を通す。

## 完了条件

- [x] PermissionRequest/PreToolUse 両フックで、有効時に審査 AI が allow/deny を返し、不確実時は人間にエスカレーションする。
- [x] ハード規則該当の危険操作は AI 判断に関わらず人間へ回る。
- [x] バックエンドが差し替え可能で、既定 codex 実機で安全/危険例を妥当に判定する。
- [x] skill validation と chezmoi managed の整合、pre-commit 相当の検証が通っている。

## 作業ログ

- 2026-05-30: 作業開始。フック仕様調査（PermissionRequest/PreToolUse の入出力・制約）、repo 規約・既存 settings・python 3.9 制約・codex 可用性を確認。設計4点（バックエンド抽象化/両フック/ask フェイルセーフ/グローバル+オプトイン）をユーザーに確認し計画承認。
- 2026-05-30: `dot_claude/hooks/supervisor/`（orchestrator・judge-codex・judge-mock・supervisor.json・prompt-template・README）と `dot_claude/settings.json` を実装。orchestrator 単体7ケースと codex 実機2ケースが期待通り（安全例 allow / 範囲外書込 deny / fail-safe で ask）。`check-chezmoi-managed.sh` を更新。
