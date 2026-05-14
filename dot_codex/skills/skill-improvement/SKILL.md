---
name: skill-improvement
description: Codex skills や Claude Code skills を点検し、役割の混線、危険な tool 許可、冗長な本文、トリガー説明の弱さを改善する。「skill 改善」「スキルを見直して」「SKILL.md を改善して」などの依頼で使用。
metadata:
  short-description: skill 改善
---

# Skill Improvement

既存 skill を、発火条件が明確で、短く、検証しやすい形へ改善する。

## 手順

1. 対象と代表ユースケースを決める。
   - 対象 skill が明示されていなければ、変更理由とリスクが一番大きいものを選ぶ。
   - repo ルール、chezmoi mapping、公開安全性の制約を先に読む。
   - ユーザーが達成したいことを 2〜3 個、trigger phrase と期待結果つきで書き出す。
   - problem-first か tool-first かを見て、skill の責務を絞る。
2. 現状を監査し、成功基準を置く。
   - `name` と `description` が実際の役割と一致しているか。
   - `description` に what, when, key capabilities があり、自然言語 trigger として十分具体的か。
   - 本文に別 runtime/tool/vendor の前提が混ざっていないか。
   - `allowed-tools` が過剰でないか。
   - scripts, references, assets へ分けるべき長い説明が本文に残っていないか。
   - secret, private URL, host-specific path, machine-local identity values がないか。
   - 成功基準は「関連依頼で発火する」「無関係な依頼で発火しない」「ユーザー補正なしに完了する」を最低限見る。
3. 改善方針を小さく決める。
   - 役割が違う場合は、本文の調整より rename/delete/split を優先する。
   - undertriggering は具体的な trigger phrase を足す。overtriggering は対象外条件やより狭い scope で直す。
   - 手順は実行順に並べ、判断基準と失敗時の扱いだけを書く。一般論は削る。
   - 失敗すると危険な検証や繰り返し作業は、可能なら script 化する。
4. 必要最小限の編集を行う。
   - 既存の skill 体系とファイル配置に合わせる。
   - product-specific metadata がある場合は本文と同期する。
5. 実行確認を行う。
   - skill validation script があれば実行する。
   - 対象 skill が参照する scripts/templates/assets の存在を確認する。
   - Trigger test: 発火すべき依頼、言い換え、発火すべきでない依頼を確認する。
   - Functional test: 代表ユースケースで期待する成果物、tool 呼び出し、エラー処理が成立するか確認する。
   - 必要なら baseline と比較し、会話往復、失敗回数、手戻りが減ったかを見る。
6. 結果を短く報告する。
   - 変更した skill
   - 改善した問題
   - 実行した検証
   - 残した判断事項

## 判断基準

- Skill は「知らないと失敗しやすい手順」だけを書く。
- Agent が通常能力で判断できる一般論は削る。
- ひとつの skill に複数の責務が混ざるなら分割する。
- 別 runtime 専用の内容は、その runtime 側の skill か command に移す。
- private/local な値を入れない。
