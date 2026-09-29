#!/usr/bin/env bash
# E2E 用のアプリサーバーを停止し、一時ファイルを片付ける。
# **E2E を回したら必ず実行する。** 止め忘れるとセッションが終了できなくなる。
set -uo pipefail

PIDFILE=/tmp/teamtasks_e2e.pid

if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
  echo "stopped"
else
  # PID ファイルが無くても、残っていれば落とす
  pkill -f "uvicorn app.main:app" 2>/dev/null && echo "stopped (by pattern)" || echo "not running"
fi

rm -f /tmp/teamtasks_e2e.db /tmp/teamtasks_e2e.log
exit 0
