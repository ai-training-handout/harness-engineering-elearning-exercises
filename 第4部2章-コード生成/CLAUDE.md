# TeamTasks 開発ルール

仕様の唯一の正は `spec.md`。判断に迷ったら spec.md に従う。spec.md に書かれていないことは実装しない。

## スタックと構成

- Python 3.11+ / FastAPI / SQLite（標準ライブラリ `sqlite3`）/ Jinja2 + HTMX / pytest
- ORM・マイグレーションツール・フロントエンドのビルドツールは使わない
- Starlette 1.x の `TemplateResponse` は `request` を第1引数に取る（`templates.TemplateResponse(request, "x.html", {...})`）。旧形式 `TemplateResponse("x.html", {"request": request})` は画面表示時に 500 になり、pytest では気づきにくい（2026-09 の検証で実際に起きた）

```
app/
  main.py        FastAPI アプリ本体・ルーティング
  db.py          sqlite3 接続とスキーマ初期化・シード投入
  models.py      Pydantic モデル（入力検証）
  auth.py        セッションとログイン中ユーザーの取得
  templates/     Jinja2 テンプレート
tests/           pytest
e2e/             Playwright シナリオ
```

<!-- ▼ Step 1 で埋める。空欄は「（ここに書く）」で示している。埋めたらこの行ごと消してよい。
     上の「スタックと構成」は spec.md §1 の写しなので埋めた状態で配っている（読むだけでよい）。
     ディレクトリ構成（main.py / db.py …）は雛形の例。spec.md はファイル分割を指定していないので、
     planner が別の構成を出したら、この表を planner の計画に合わせて更新してよい ▼ -->

## コーディング規約

- （ここに書く：型ヒント・docstring）
- （ここに書く：SQL の置き場所。ルーティング層に生 SQL を書かせない）
- （ここに書く：入力検証をどこで行うか）
- （ここに書く：日時の扱い。UTC・ISO8601）

## Do NOT（違反は実装のやり直し）

- （ここに書く：テストを削除・skip・期待値の書き換えで green にしない）
- （ここに書く：spec.md にない機能を追加しない）
- （ここに書く：`_instructor/` を読まない・参照しない）
- （必要なら追加：依存を増やさない・秘密情報をコードに書かない など）

<!-- ▲ Step 1 ここまで ▲ -->

## 注意（この題材の割り切り）

認証はパスワードなしの簡易ログインである。これは**研修題材として実装量を抑えるための割り切り**であり、実運用の認証設計ではない。この方式を実務のリファレンスにしないこと。

## 作業の進め方

1. `spec.md` を読み、`plan.md` に計画（作るファイル・関数・テスト項目）を出す。
2. 計画に沿って実装する。
3. `pytest` と E2E で検証する。落ちたら実装を直して再検証する（上限は `/implement` の定義に従う）。
4. green になったらブランチを切り、変更概要とテスト結果を含む PR 本文を作る。
