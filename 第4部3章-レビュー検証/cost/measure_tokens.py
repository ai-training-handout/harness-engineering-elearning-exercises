#!/usr/bin/env python3
"""Claude Code の transcript からトークン消費を集計する。

レビューハーネスの実行ごとに走らせ、条件（並列/逐次/上限装置あり）ごとの
消費量を比較するために使う。実測値は cost/実測結果.md に転記する。

使い方:
    # 直近の transcript を集計してラベルを付けて記録する
    python3 cost/measure_tokens.py --label "4観点並列"

    # 特定の transcript を指定する
    python3 cost/measure_tokens.py --label "逐次" --transcript ~/.claude/projects/.../xxx.jsonl

    # 記録済みの結果を表形式で出す
    python3 cost/measure_tokens.py --report
"""

from __future__ import annotations

import argparse
import glob
import json
import os
from datetime import datetime, timezone
from pathlib import Path

RECORD_DIR = Path(__file__).parent / "measurements"

# 参考単価（USD / 100万トークン）。実際の単価は必ず公式の料金表で確認すること。
# 教材で金額を示す場合は、この定数を確認日つきで更新する。
PRICE_PER_MTOK = {"input": 15.0, "output": 75.0, "cache_read": 1.5, "cache_write": 18.75}


def latest_transcript() -> str | None:
    """cwd に対応する transcript の最新を返す。

    複数セッションを同時に開いた状態（並列計測の最中など）で単純に mtime 最大を選ぶと、
    **別セッションの最後に書かれたファイルを掴む**（2026-08 の並列計測で実際に発生）。
    各候補の記録に含まれる `cwd` が現在の作業ディレクトリと一致するものだけに絞ってから
    最新を選ぶ。エンコードされた project ディレクトリ名の再構成には依存しない。
    確実を期すなら `--transcript` で明示するのが最も安全。
    """
    candidates = glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))
    if not candidates:
        return None
    here = os.path.realpath(os.getcwd())

    def matches_cwd(path: str) -> bool:
        try:
            with open(path, encoding="utf-8") as f:
                for line in f:
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    cwd = rec.get("cwd")
                    if cwd:
                        return os.path.realpath(cwd) == here
        except OSError:
            return False
        return False

    scoped = [c for c in candidates if matches_cwd(c)]
    return max(scoped or candidates, key=os.path.getmtime)


def subagent_transcripts(main_path: str) -> list[str]:
    """メイン transcript に対応するサブエージェントの transcript を集める。

    Claude Code はサブエージェント（reviewer / aggregator）の記録を
    `<プロジェクトdir>/<sessionId>/` 配下の別ファイル（`agent-*.jsonl`）に分離する。
    メイン jsonl だけ集計するとこの分（1レビューで数十万トークン）が丸ごと漏れる。
    """
    session_id = Path(main_path).stem
    sub_dir = Path(main_path).parent / session_id
    if not sub_dir.is_dir():
        return []
    return [str(p) for p in sub_dir.glob("**/*.jsonl")]


def _usage_of_file(path: str) -> tuple[dict, int, str | None, str | None]:
    """transcript 1本を message id で重複排除して集計する。

    同一 API 呼び出しの usage が複数行に記録されることがあり（現行の Claude Code で確認・
    2026-08-26）、行単位で素朴に足すと実消費の2倍以上に膨れる。message.id（無ければ uuid）を
    キーに最後の値で上書きし、1呼び出しを1回だけ数える。
    """
    seen: dict = {}
    first_ts = last_ts = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            ts = rec.get("timestamp")
            if ts:
                first_ts = first_ts or ts
                last_ts = ts
            msg = rec.get("message") or {}
            usage = msg.get("usage") or {}
            if not usage:
                continue
            key = msg.get("id") or rec.get("uuid")
            seen[key] = {
                "input": usage.get("input_tokens", 0),
                "output": usage.get("output_tokens", 0),
                "cache_read": usage.get("cache_read_input_tokens", 0),
                "cache_write": usage.get("cache_creation_input_tokens", 0),
            }
    totals = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}
    for v in seen.values():
        for k in totals:
            totals[k] += v[k]
    return totals, len(seen), first_ts, last_ts


def summarize(path: str) -> dict:
    """メイン＋サブエージェントの transcript をまとめてトークン消費を集計する。"""
    totals = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}
    calls = 0
    first_ts = last_ts = None

    for fp in [path] + subagent_transcripts(path):
        t, c, f0, l0 = _usage_of_file(fp)
        for k in totals:
            totals[k] += t[k]
        calls += c
        if f0:
            first_ts = f0 if (first_ts is None or f0 < first_ts) else first_ts
        if l0:
            last_ts = l0 if (last_ts is None or l0 > last_ts) else last_ts

    total_tokens = sum(totals.values())
    cost = sum(totals[k] / 1_000_000 * PRICE_PER_MTOK[k] for k in totals)

    elapsed = None
    if first_ts and last_ts:
        try:
            fmt = "%Y-%m-%dT%H:%M:%S.%f%z"
            t0 = datetime.strptime(first_ts.replace("Z", "+0000"), fmt)
            t1 = datetime.strptime(last_ts.replace("Z", "+0000"), fmt)
            elapsed = round((t1 - t0).total_seconds())
        except ValueError:
            elapsed = None

    return {
        "transcript": path,
        "api_calls": calls,
        "tokens": totals,
        "total_tokens": total_tokens,
        "estimated_cost_usd": round(cost, 2),
        "elapsed_sec": elapsed,
    }


def record(label: str, summary: dict) -> Path:
    RECORD_DIR.mkdir(exist_ok=True)
    summary = dict(summary, label=label, measured_at=datetime.now(timezone.utc).isoformat())
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in label)
    out = RECORD_DIR / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}-{safe}.json"
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


def report() -> None:
    files = sorted(RECORD_DIR.glob("*.json")) if RECORD_DIR.exists() else []
    if not files:
        print("記録がありません。--label を付けて計測してください。")
        return
    print("| 条件 | 合計トークン | 入力 | 出力 | キャッシュ読 | API 回数 | 所要秒 | 概算 USD |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    for f in files:
        d = json.loads(f.read_text(encoding="utf-8"))
        t = d["tokens"]
        print(
            f"| {d['label']} | {d['total_tokens']:,} | {t['input']:,} | {t['output']:,} | "
            f"{t['cache_read']:,} | {d['api_calls']} | {d.get('elapsed_sec') or '-'} | "
            f"{d['estimated_cost_usd']} |"
        )


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--label", help="この実行の条件名（例：4観点並列 / 逐次 / 上限装置つき）")
    p.add_argument("--transcript", help="集計する transcript のパス（既定：最新）")
    p.add_argument("--report", action="store_true", help="記録済みの結果を表で出す")
    args = p.parse_args()

    if args.report:
        report()
        return

    path = args.transcript or latest_transcript()
    if not path or not os.path.exists(path):
        raise SystemExit("transcript が見つかりません。--transcript で指定してください。")

    summary = summarize(path)
    t = summary["tokens"]
    print(f"transcript : {path}")
    print(f"API 呼び出し: {summary['api_calls']} 回")
    print(f"合計トークン: {summary['total_tokens']:,}")
    print(f"  入力 {t['input']:,} / 出力 {t['output']:,} / "
          f"キャッシュ読 {t['cache_read']:,} / キャッシュ書 {t['cache_write']:,}")
    print(f"所要時間   : {summary['elapsed_sec'] or '-'} 秒")
    print(f"概算コスト : ${summary['estimated_cost_usd']}（単価は要確認）")

    if args.label:
        out = record(args.label, summary)
        print(f"記録しました: {out}")


if __name__ == "__main__":
    main()
