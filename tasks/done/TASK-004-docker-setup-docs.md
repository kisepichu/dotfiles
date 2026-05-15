# TASK-004: docker-setup-docs

## 参照仕様

- docs/plan.md
- docs/tooling-strategy.md
- README.md
- scripts/install-docker-engine-wsl.sh

## チェックリスト

- [x] fresh WSL bootstrap の確認済み状態を docs に反映する。
- [x] Windows/WSL の人間向け初回手順を README に移す。
- [x] 古い Windows 側 Docker 前提の記述を消し、WSL Ubuntu 内 Docker Engine 方針へ更新する。
- [x] Docker Engine の idempotent install script を追加する。
- [x] 手順と script の静的検証を通す。

## 完了条件

- [x] README から fresh WSL bootstrap と Docker Engine 導入手順を追える。
- [x] Windows 側 Docker app を採用候補として残していない。
- [x] `prek run --all-files` が通る。

## 作業ログ

- 2026-05-15: 作業開始。fresh WSL bootstrap 確認済みの前提で Docker setup/docs を更新する。
- 2026-05-15: README と Docker Engine install script を追加。`bash -n scripts/install-docker-engine-wsl.sh` と `prek run --all-files` が通過。
- 2026-05-15: `chezmoi-dotfiles-test` WSL distro で Docker Engine install script を実行。systemd 有効化後、通常ユーザーで `docker run --rm hello-world` と `docker compose version` が通過。
