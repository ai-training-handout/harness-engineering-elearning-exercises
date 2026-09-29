#!/usr/bin/env bash
# Stop Hook：応答が終わるたびに完了を知らせ、このセッションの消費トークンを集計して表示する。
# 集計はサブエージェント（planner・implementer・reviewer）の分も含む、セッションの最初からの累計。
# 条件ごとに測るときは、測る前に /exit して claude を起動し直し、新しいセッションで始める。
# 「測っていること自体」を演習で見せるのが目的（コスト管理の入口）。
set -uo pipefail

payload=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage": "ハーネスの1サイクルが終了しました。トークン集計：python3 が見つからないため集計できませんでした"}'
  exit 0
fi

# 画面に出すには JSON の systemMessage で返す。
# Stop hook の素の標準出力は、対話画面にも ctrl+o の詳細表示にも出ない（2026-09-26 確認・Claude Code 2.1.283）。
printf '%s' "$payload" | python3 -c '
import glob, json, os, sys
from datetime import datetime

def summarize(payload_text):
    try:
        path = json.loads(payload_text or "{}").get("transcript_path") or ""
    except ValueError:
        path = ""
    if not path or not os.path.isfile(path):
        return None, "トークン集計：会話記録を取得できませんでした"
    # メインの記録と、同じセッションのサブエージェントの記録（<セッションID>/subagents/*.jsonl）
    files = [path] + sorted(glob.glob(os.path.join(path[:-len(".jsonl")], "subagents", "*.jsonl")))
    seen = {}
    first = last = None
    for fp in files:
        try:
            with open(fp, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    ts = rec.get("timestamp")
                    if isinstance(ts, str):
                        first = min(first, ts) if first else ts
                        last = max(last, ts) if last else ts
                    msg = rec.get("message") or {}
                    usage = msg.get("usage") if isinstance(msg, dict) else None
                    if not isinstance(usage, dict):
                        continue
                    # 同じ API 呼び出しが中身ごとに複数行に記録されるので、message.id で1回だけ数える
                    key = msg.get("id") or rec.get("uuid") or (fp, len(seen))
                    def n(k):
                        v = usage.get(k, 0)
                        return v if isinstance(v, int) else 0
                    seen[key] = (n("input_tokens"), n("output_tokens"),
                                 n("cache_read_input_tokens"), n("cache_creation_input_tokens"))
        except OSError:
            continue
    if not seen:
        return None, "トークン集計：会話記録に使用量がまだ記録されていません"
    inp, out, cr, cw = (sum(v[i] for v in seen.values()) for i in range(4))
    total = inp + out + cr + cw
    minutes = ""
    try:
        t0 = datetime.fromisoformat(first.replace("Z", "+00:00"))
        t1 = datetime.fromisoformat(last.replace("Z", "+00:00"))
        minutes = f"・経過 {(t1 - t0).total_seconds() / 60:.1f} 分"
    except Exception:
        pass
    return total, (f"消費トークン集計（このセッションの累計・サブエージェント込み）  合計 {total:,} / "
                   f"入力 {inp:,} / 出力 {out:,} / キャッシュ読み {cr:,} / キャッシュ書き {cw:,}"
                   f"（API 呼び出し {len(seen)} 回{minutes}）")

try:
    total, summary = summarize(sys.stdin.read())
except Exception as e:
    total, summary = None, f"トークン集計：失敗しました（{type(e).__name__}）"
tail = "（Step 10 の表に転記する）" if total is not None else ""
print(json.dumps({"systemMessage": "ハーネスの1サイクルが終了しました。" + summary + tail}, ensure_ascii=False))
'

# macOS の通知（利用できない環境では黙って無視する）
if command -v osascript >/dev/null 2>&1; then
  osascript -e 'display notification "TeamTasks ハーネスの実行が終了しました" with title "Claude Code"' >/dev/null 2>&1 || true
fi

exit 0
