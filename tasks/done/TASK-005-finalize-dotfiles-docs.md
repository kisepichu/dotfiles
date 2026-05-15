# TASK-005: finalize-dotfiles-docs

## 参照仕様

- README.md
- docs/plan.md
- docs/current-state.md
- scripts/bootstrap-wsl-ubuntu.sh
- dot_config/chezmoi/chezmoi.toml.tmpl

## チェックリスト

- [x] `chezmoi init --apply` の追加導線を追わない判断を記録する。
- [x] Docker Engine は core bootstrap に含めず、任意 script のままにする判断を記録する。
- [x] repository/path 表記を `dotfiles` に統一する。
- [x] plan/current-state の次作業から完了済みの判断項目を外す。

## 完了条件

- [x] README の clone path が `kisepichu/dotfiles` と `~/repos/dotfiles` を指す。
- [x] managed chezmoi source path が `~/repos/dotfiles` を指す。
- [x] `prek run --all-files` が通る。

## 作業ログ

- 2026-05-15: PR #4 merge 後の develop から作業開始。README bootstrap 手順を正ルートとし、Docker Engine は任意導入のままにする判断を記録。
