---
name: review-report
description: レビュー所見とマージ判定を毎回同じ様式で出力する。GitHub コメント用 Markdown を併せて出す。
---

レビュー結果は必ず以下の様式で出力する。様式を毎回同じに保つことで、実行ごとの比較と機械的な集約ができる。

## 所見1件あたりの必須項目

| 項目 | 内容 |
|---|---|
| 観点 | correctness / security / performance / readability のいずれか1つ |
| 重大度 | Blocker / Major / Minor / Nit |
| 箇所 | `file:line`（行が特定できない場合は `file`） |
| 問題 | 何が問題か。**仕様のどの条項に反するか**を書けるなら書く |
| 修正提案 | どう直すか。具体的に |

## 出力形式

```markdown
## 観点：<観点名>

### 指摘 1
- **重大度**：Blocker
- **箇所**：`app/db.py:82`
- **問題**：（仕様 §x-y が要求する〜が実装されていない）
- **修正提案**：（〜する）

### 指摘 2
...
```

指摘がない場合は、観点名のあとに **「指摘なし」** とだけ書く。無理に指摘を作らない。

## GitHub コメント用 Markdown（aggregator が最後に出す）

```markdown
## 自動レビュー結果：<Approve / Request Changes / Block>

<判定理由>

<details><summary>指摘一覧（N件）</summary>

| 重大度 | 観点 | 箇所 | 問題 | 修正提案 |
|---|---|---|---|---|

</details>

観点別：correctness N件 / security N件 / performance N件 / readability N件
```

## 禁止

- 重大度を空欄にしない。
- 箇所を「全体」「複数箇所」で済ませない（代表箇所を1つ挙げる）。
- 断定できないことを断定形で書かない（確認が必要なら Minor で「要確認」と明記する）。
