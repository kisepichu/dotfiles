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
3. **ハード規則** — 危険パターンに一致したら、AI の判断に関わらず必ず人間へ
   エスカレーション。
4. **審査バックエンド呼び出し** — `judge-codex.sh` にコンテキストを渡し、
   `{"decision":"allow|deny|ask","reason":"..."}` を得る。
5. `allow`/`deny` をフック JSON に変換して出力。`ask`・タイムアウト・エラーは
   **出力なし＝人間へ**。
6. 判定を `logs/audit.jsonl` に追記。

## 有効化（オプトイン）

インストールしただけでは何もしない（`enabled: false`）。有効化する方法は2つ:

- 一時的: シェルで `export CLAUDE_SUPERVISOR=1`（`0` で強制無効）。
- 恒久的: `supervisor.json` の `"enabled": true`。

`CLAUDE_SUPERVISOR` は `supervisor.json` より優先される。

## 設定 `supervisor.json`

| キー | 意味 |
| --- | --- |
| `enabled` | 既定の有効/無効。 |
| `backend` | 審査バックエンドのスクリプト（相対なら本ディレクトリ基準、絶対パス可）。 |
| `backend_timeout_seconds` | バックエンドのタイムアウト秒。超過で人間へ。 |
| `hard_escalate_patterns` | これに一致したら常に人間へ回す正規表現の配列。 |

## バックエンドの差し替え

`backend` は `{"decision":...,"reason":...}` を stdout に返す任意の実行ファイルに
変更できる（stdin にコンテキスト JSON を受け取る契約）。同梱:

- `judge-codex.sh` — 既定。`prompt-template.md` を使って `codex exec` で判定。
- `judge-mock.sh` — テスト用。環境変数で固定 verdict を返す。

環境変数 `CLAUDE_SUPERVISOR_BACKEND` を設定すると `supervisor.json` の `backend`
を上書きできる（テストや一時利用向け）。

## 安全設計

- **オプトイン**（既定オフ）。
- **ハード規則**で危険カテゴリ（`rm -rf`, force push, `sudo`, `curl|sh`,
  資格情報・鍵など）は AI が allow と言っても必ず人間へ。
- **フェイルセーフ**: 不確実・タイムアウト・エラーは一切 allow に倒さず人間へ。
- **監査ログ** `logs/audit.jsonl`（chezmoi 管理外、実行時生成）。

## 注意

- この `settings.json` は chezmoi 管理。`/config` でのテーマ変更等はここで管理
  する（`chezmoi apply` で上書きされるため）。
- フックに会話履歴は渡らない。審査 AI が見られるのはツール情報＋cwd のみで、
  文脈は限定的。だからこそ「迷ったら人間へ」の設計になっている。
