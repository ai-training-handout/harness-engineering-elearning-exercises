#!/usr/bin/env bash
# E2E 用のアプリサーバーを起動する。
# 単一コマンドにしてあるのは、Permissions の allow で1行で許可できるようにするため
# （環境変数の前置き・バックグラウンド化・PID の保存を1つのコマンドに含めると、
#  複合コマンドとして扱われて承認待ちで止まる）。
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1

PORT="${1:-8765}"
DB=/tmp/teamtasks_e2e.db
PIDFILE=/tmp/teamtasks_e2e.pid

# 既に動いていれば落としてから起動する（ポート衝突の予防）
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi
rm -f "$DB"

# `uv run uvicorn` ではなく `python -m uvicorn` で起動する（環境によっては uvicorn のコンソールスクリプトが
# 見つからず Failed to spawn になる。2026-09 の WSL 検証で発生）
TEAMTASKS_DB="$DB" uv run python -m uvicorn app.main:app --port "$PORT" >/tmp/teamtasks_e2e.log 2>&1 &
echo $! > "$PIDFILE"

# 起動を待つ（最大15秒）
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "http://127.0.0.1:${PORT}/login"; then
    echo "started on http://127.0.0.1:${PORT} (pid $(cat "$PIDFILE"))"
    exit 0
  fi
  sleep 0.5
done

echo "サーバーの起動に失敗しました。/tmp/teamtasks_e2e.log を確認してください。" >&2
exit 1
