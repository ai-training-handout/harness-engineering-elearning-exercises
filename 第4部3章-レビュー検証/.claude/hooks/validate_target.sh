#!/usr/bin/env bash
# UserPromptSubmit Hook：レビュー対象を実行「前」に検証する。
# ねらい：対象を取り違えたまま4並列を回すと、間違った対象にコストを払うことになる。
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

payload=$(cat)
prompt=$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null)

# /review 以外のプロンプトには干渉しない
case "$prompt" in
  */review*) ;;
  *) exit 0 ;;
esac

fail() {
  echo "レビュー対象の検証に失敗しました: $1" >&2
  echo "対象を確認してから再実行してください（誤った対象へのレビューはコストの無駄になります）。" >&2
  exit 2
}

# ケース1：固定サンプル PR（ローカルディレクトリ）
if printf '%s' "$prompt" | grep -q 'sample-pr'; then
  [ -d "./sample-pr" ] || fail "sample-pr ディレクトリが存在しません"
  [ -f "./sample-pr/PR.md" ] || fail "sample-pr/PR.md がありません（PR 本文は必須の入力です）"
  exit 0
fi

# ケース2：実 PR（#123 形式）
num=$(printf '%s' "$prompt" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
if [ -n "$num" ]; then
  printf '%s' "$num" | grep -qE '^[0-9]+$' || fail "PR 番号の形式が不正です: $num"
  if command -v gh >/dev/null 2>&1; then
    gh pr view "$num" --json number >/dev/null 2>&1 || fail "PR #$num がこのリポジトリに見つかりません"
  else
    echo "注意: gh コマンドが無いため PR #$num の存在確認をスキップしました" >&2
  fi
  exit 0
fi

fail "レビュー対象を特定できません（'sample-pr' か PR 番号 '#123' を指定してください）"
