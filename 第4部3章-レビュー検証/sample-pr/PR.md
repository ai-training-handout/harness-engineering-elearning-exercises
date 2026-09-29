# 仕様変更：タスク検索・絞り込み機能の追加

## 変更概要

`GET /tasks`（HTML）・`GET /api/tasks`（JSON）に **検索・絞り込み・ソート・ページネーション** を追加した。両エンドポイントは同一のクエリパラメータで同一の絞り込み結果を返す。SQL は `app/db.py` に集約し、権限（member は自分の関与タスクのみ）との合成、`priority` の意味順ソート、`due_date` NULL の末尾配置、`overdue` の当日境界扱いをすべて SQL 側で行っている。一覧応答は `{items, total, page, per_page, total_pages}` の5キー形状に変わった。

## 実装した仕様条項（spec-search.md）

- クエリパラメータ表（12 項目）：`q`・`status`（複数可）・`priority`・`tag`・`assignee_id`・`due_from`・`due_to`・`overdue`・`sort`・`order`・`page`・`per_page`。制約列（enum 外/形式不正/範囲外は 422、`due_from > due_to` は 422、`overdue` は `"true"` のみ許容）まで Pydantic の `SearchQuery` で検証。
- 正しさ 1（AND 合成）：`_build_search_where` で全条件を AND 連結。
- 正しさ 2（権限との合成）：member は `(created_by = ? OR assignee_id = ?)` を WHERE 句に組み込み、SQL 段階で絞り込む。
- 正しさ 3（`priority` の意味順ソート）：`ORDER BY CASE priority WHEN 'urgent' 0 ... 'low' 3 END` を使い、辞書順にしない。
- 正しさ 4（`due_date` NULL）：`due_date IS NULL ASC` を先頭に付けて asc/desc とも NULL を末尾に。範囲・overdue 指定時は `due_date IS NOT NULL` を AND。
- 正しさ 5（応答形状）：`{items, total, page, per_page, total_pages}` を返す。範囲外ページは空リスト 200。
- 正しさ 6（SQL レベルの絞り込み）：Python 側での事後フィルタは行わない。
- 正しさ 7（UI）：検索フォーム／総件数表示／0件時メッセージ／ページャ（クエリ保持）／HTMX 部分差し替え。

## 手順2で落ちた既存テストと仕分け

- **`tests/test_list.py::test_list_empty`**：応答を `{"items": [], "total": 0}` と厳密比較していたテストが失敗。spec-search.md 正しさ5により応答が5キー形状（`page/per_page/total_pages` を含む）に変わった **期待値そのものが変わったケース**。テストの意図（未ログイン/空状態で 200・空 items・total 0）を保ったまま、期待値を新形状に更新した。
- 落ちたテストはこの 1 件のみ。他の既存テスト（CRUD・権限・HTML 一覧など）は変更なしで通り続けた。

追加テスト：
- `tests/test_search.py`：spec-search.md のテスト要件 1〜8 を網羅（`q` 部分一致・大文字小文字無視／`status` 複数・`priority`・`tag`・`assignee_id`／`due_from`・`due_to` 境界と `due_from > due_to`=422／`overdue` 前日含む・当日含まない・`done` 除外／`priority` 意味順 asc/desc／`due_date` NULL 末尾／`sort`/`order` 422／権限との合成（admin/member の件数差）／`page`/`per_page` 境界（0/101 → 422、範囲外 page → 空 200）／AND 複合／応答 5 キー／既定値）。
- `tests/test_search_html.py`：HTML と JSON が同一絞り込み結果、HTMX 断片応答、検索条件がページャに保持、0 件時メッセージ。

## テスト結果

```sh
uv run pytest -q
```

- **82 passed**（既存 48 + 新規 34）
- 落ちたテスト：0

E2E（Playwright MCP、`e2e/scenario.md`）：

1. `member1` でログイン → `/tasks` に遷移し、ヘッダに `ログイン中: member1` が表示。
2. 新規作成フォームで `e2e search task` を作成 → **ページ全リロードなし（HTMX 部分更新）** に一覧の先頭へ表示される。
3. 詳細 `/tasks/2` を開き、タイトル・status・priority・期限・担当・タグが表示されている。
4. status を `doing` に変更 → 部分更新で `status: doing` に切り替わる。
5. 一覧に戻ると `[doing]` 表示。総件数 `2`、ページャ `1 / 1`。
6. ログアウトで `/login` に遷移、`/tasks` を再度開くと `/login` にリダイレクト。

**Verify の実行回数：1回**（pytest・E2E とも初回で green）。

## レビュー観点

- SQL 集約の徹底：`app/main.py` の `_parse_search` は入力整形のみで、`app/db.py::search_tasks` に WHERE/ORDER/LIMIT がすべて集約されているか。
- `priority` ソートの CASE 式が意味順（`desc` で urgent が先頭）になっているか。
- `overdue` が `date.today()` を Python 側で決定し、SQL 上は `due_date < ?`（`<=` にしない）で当日を含まないことを担保できているか。
- `due_date` NULL の扱いが「ソート時は末尾／範囲・overdue 対象外」で分岐しているか。
- HTML（HTMX 断片）と JSON（5 キー応答）が同じ `search_tasks` 経路を通っているか。
- 検索フォームの各 `<select>`・`<input>` のクエリ保持と、ページャリンクにクエリが伝播しているか。
- 手順2で落ちた既存テスト（`test_list_empty`）の期待値更新が **仕様変更に沿った意図保持** の修正であること。

## pytest の出力（原文）

```
$ uv run pytest -q
82 passed
```

すべて green です。レビューをお願いします。
