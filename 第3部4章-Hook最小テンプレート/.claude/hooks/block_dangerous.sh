#!/usr/bin/env bash
# PreToolUse Hook（第3部4章 #127・#133 の最小テンプレート）：危険な Bash コマンドを実行前に止める。
# 書き換えるのは「▼ ここを自分のプロジェクトに合わせる」の case の中だけ。
# 条件に当たれば exit 2（実行を止め、標準エラー出力の文言が理由として LLM に渡る）。外れれば exit 0（素通り）。

# 標準入力の JSON から、実行しようとしているコマンドを取り出す（jq があれば jq -r '.tool_input.command' でもよい）
cmd=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))' 2>/dev/null)

# ▼ ここを自分のプロジェクトに合わせる（止めたい操作を1行ずつ。* は任意の文字列）
case "$cmd" in
  *"git push"*" -f"*|*"git push"*"--force"*)
    echo "force push は履歴を壊すためブロックしました。通常の push にするか、人に確認してください" >&2; exit 2 ;;
  *"DROP TABLE"*|*"--env=production"*)
    echo "本番に触れる操作のためブロックしました" >&2; exit 2 ;;
esac
# ▲ ここまで

exit 0
