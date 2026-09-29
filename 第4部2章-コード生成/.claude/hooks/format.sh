#!/usr/bin/env bash
# PostToolUse Hook：Python ファイルを編集するたびに整形と lint を走らせる。
# 方針：成功したときは沈黙し、失敗したときだけ冗長に出す（ノイズを増やさない）。
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# 変更対象が Python でなければ何もしない
payload=$(cat)
file=$(printf '%s' "$payload" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
case "$file" in
  *.py) ;;
  *) exit 0 ;;
esac

if ! command -v uv >/dev/null 2>&1; then
  exit 0
fi

out=$(uv run ruff format "$file" 2>&1) || {
  echo "ruff format に失敗しました:" >&2
  echo "$out" >&2
  exit 2
}

out=$(uv run ruff check --fix "$file" 2>&1) || {
  echo "ruff check で未解決の指摘があります。実装を修正してください:" >&2
  echo "$out" >&2
  exit 2
}

exit 0
