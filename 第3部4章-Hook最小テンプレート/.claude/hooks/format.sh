#!/usr/bin/env bash
# PostToolUse Hook（第3部4章 #133 の最小テンプレート）：ファイルを編集するたびに formatter をかける。
# 書き換えるのは「▼ ここを自分のプロジェクトに合わせる」の case の中だけ。
# 方針：成功したときは何も出さない。失敗したときだけ理由を出して exit 2（LLM に理由が渡り、直しに行く）。
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# 標準入力の JSON から、編集されたファイルのパスを取り出す（jq が無くても動くよう python3 で読む）
file=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' 2>/dev/null)
[ -n "$file" ] || exit 0

# ▼ ここを自分のプロジェクトに合わせる（拡張子ごとに、かけたい formatter を1行ずつ）
case "$file" in
  *.py)             cmd=(ruff format "$file") ;;
  *.ts|*.tsx|*.js)  cmd=(npx --no-install prettier --write "$file") ;;
  *)                exit 0 ;;   # それ以外のファイルは何もしない
esac
# ▲ ここまで

command -v "${cmd[0]}" >/dev/null 2>&1 || exit 0   # formatter が入っていない環境では何もしない

out=$("${cmd[@]}" 2>&1) || {
  echo "整形に失敗しました（${cmd[*]}）:" >&2
  echo "$out" >&2
  exit 2
}
exit 0
