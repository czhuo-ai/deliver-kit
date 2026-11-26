"""验收脚本：把一组问题打给已部署的服务，出一份能签字的结果。

用法：
    python accept.py --url http://127.0.0.1:8000 --cases cases.jsonl --out 验收报告.md

验收和评测的区别：
    评测是开发自己看的（指标怎么变），验收是给客户看的（哪些过、哪些不过、为什么）。
所以每条只判「该答的答对没有 / 不该答的有没有拒」，不纠结分数高低。
"""
import argparse
import json
import os
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def ask(url, question, timeout=30):
    body = json.dumps({"question": question}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url.rstrip("/") + "/ask",
        data=body,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode("utf-8"))
    return data, int((time.time() - t0) * 1000)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8000")
    ap.add_argument("--cases", default=os.path.join(HERE, "cases.jsonl"))
    ap.add_argument("--out", default=os.path.join(HERE, "验收报告.md"))
    args = ap.parse_args()

    cases = [json.loads(l) for l in open(args.cases, encoding="utf-8") if l.strip()]
    rows, passed, total_ms = [], 0, 0

    for i, c in enumerate(cases, 1):
        try:
            data, ms = ask(args.url, c["q"])
            answer = (data.get("answer") or "").strip()
            refused = bool(data.get("refused"))
            total_ms += ms
            if c.get("answerable", True):
                # 该答的：不能拒答，且要包含至少一个关键词
                hit = (not refused) and any(k in answer for k in c.get("keywords", [c["q"]]))
            else:
                # 不该答的：必须拒答
                hit = refused
            ok = "✅" if hit else "❌"
            if hit:
                passed += 1
            rows.append((i, c["q"], "应回答" if c.get("answerable", True) else "应拒答", ok, ms, answer.replace("\n", " ")[:60]))
        except Exception as e:
            rows.append((i, c["q"], "-", "❌", 0, f"请求失败：{type(e).__name__}: {e}"))

    rate = passed / len(cases) * 100 if cases else 0
    L = []
    L.append("# 交付验收报告")
    L.append("")
    L.append(f"- 服务地址：{args.url}")
    L.append(f"- 验收时间：{time.strftime('%Y-%m-%d %H:%M:%S')}")
    L.append(f"- 用例数：{len(cases)}　通过：{passed}　通过率：{rate:.1f}%")
    L.append(f"- 平均响应：{total_ms // max(len(cases), 1)} ms")
    L.append("")
    L.append("## 逐条结果")
    L.append("")
    L.append("| # | 问题 | 期望 | 结果 | 耗时 | 回答（截断） |")
    L.append("|---|---|---|---|---|---|")
    for r in rows:
        L.append(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} ms | {r[5]} |")
    L.append("")
    fails = [r for r in rows if r[3] == "❌"]
    L.append("## 结论")
    L.append("")
    if not fails:
        L.append(f"**{len(cases)} 条全部通过**，可按此报告验收。")
    else:
        L.append(f"**{len(fails)} 条未通过**，需修复后重验：")
        L.append("")
        for r in fails:
            L.append(f"- 第 {r[0]} 条「{r[1]}」：{r[5]}")

    open(args.out, "w", encoding="utf-8").write("\n".join(L))
    print("\n".join(L))
    print(f"\n报告已存：{args.out}")
    return 0 if not fails else 1


if __name__ == "__main__":
    raise SystemExit(main())
