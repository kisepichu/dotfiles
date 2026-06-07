# TASK-015: 管理対象 Mac で Nix インストールが失敗する問題の修正

## 参照仕様

- User report on 2026-06-07: `scripts/install-nix.sh` を実行しても Nix がインストールされない。会社 PC (managed Mac) が原因の疑い。同僚も別手段で同様の問題を報告。
- 関連: TASK-011 (install-nix.sh の初期実装)

## 調査結果

### 根本原因: DiskArbitrationDissenter

`/var/log/determinate-nix-init.log` に 3 回のインストール試行が記録されており、毎回 `dissenter: Some(DiskArbitrationDissenter)` で APFS ボリューム作成に失敗していた。

**Digital Guardian** (企業セキュリティソフト `/usr/local/dgagent/`) が DiskArbitration dissenter として登録されており、Nix 用 APFS ボリューム ("Nix Store") の作成をブロックしている。

結果:
- `/etc/nix/macos-keychain.crt` だけ残り (`2026-06-02 12:25`)、`/nix` ボリュームは未作成
- LaunchDaemon・receipt はインストーラの revert で削除済み
- `/etc/synthetic.conf` も存在しない

### 副次的問題

1. **GID/UID 衝突**: GID 350 (`_avectodaemon`), 351 (`_defendpoint`) が既に使用済み。auto-detection コードは TASK-011 後に追加済み (未コミット) で、GID 352 / UID base 352 を正しく検出。
2. **Digital Guardian ACL エラー**: DG が `com.dgagent.*` xattr を付与し、Nix が未知の ACL としてエラーにする。`/etc/nix/nix.conf` に `ignored-acls` 設定が必要 (同僚の報告 `tmp/a.md` と一致)。

## 修正内容

`scripts/install-nix.sh` に以下を追加:

1. **前回失敗のクリーンアップ**: `/etc/nix` が残っているが `/nix/var/nix` が無い状態を検出し `sudo rm -rf /etc/nix`
2. **synthetic.conf + APFS ボリューム事前作成**: インストーラ実行前に `diskutil apfs addVolume` でボリュームを作成。インストーラがボリューム検出してスキップすることで DiskArbitrationDissenter を回避
3. **Digital Guardian ignored-acls**: インストール後に `dgdaemon` プロセスを検出し、`/etc/nix/nix.conf` に `ignored-acls` を自動追加

## チェックリスト

- [x] 前回失敗のクリーンアップ処理
- [x] `/etc/synthetic.conf` への `nix` エントリ追加 + `apfs.util -t` 適用
- [x] APFS ボリューム事前作成 (`diskutil apfs addVolume`)
- [x] Digital Guardian `ignored-acls` 自動設定
- [x] GID/UID auto-detection (TASK-011 後に追加済み、本タスクで統合)
- [x] `bash -n` 構文チェック通過
- [x] 実機テスト (`scripts/install-nix.sh` 実行)
- [x] `conf.d/nix.fish` を Determinate Nix の profile パスに対応

## 完了条件

- [x] `scripts/install-nix.sh` が管理対象 Mac の既知問題 (DiskArbitrationDissenter, GID/UID 衝突, Digital Guardian ACL) に対応
- [x] 実機で Nix インストールが成功する

## 注意事項

- `ignored-acls` は Lix 固有のオプション。Determinate Nix (upstream) では未サポート。スクリプトは `nix show-config` で対応可否を検出し、未対応時はヒントメッセージのみ出力。
- Determinate Nix は設定を `nix.conf` (自動管理) + `nix.custom.conf` (ユーザー) に分離。ユーザー設定は `nix.custom.conf` に書く。

## 作業ログ

- 2026-06-07: 調査開始。`/var/log/determinate-nix-init.log` から DiskArbitrationDissenter を特定。Digital Guardian プロセス確認、GID/UID 衝突状況確認。修正実装 (クリーンアップ + APFS 事前作成 + ignored-acls)。
- 2026-06-07: 実機テスト成功。PATH 問題を発見 — `conf.d/nix.fish` が `~/.nix-profile` を参照していたが Determinate Nix は `/nix/var/nix/profiles/default` にプロファイルを置く。nix.fish を修正。`ignored-acls` が Determinate Nix で未サポートと判明、スクリプトのDG対応をバージョン検出方式に変更。
