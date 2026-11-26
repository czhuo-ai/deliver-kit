"""探一下模型接口通不通。PowerShell 在部分机器上 TLS 会挂，所以用 Python 探。

用法：python ping_model.py <apiBase> <apiKey>
输出：ok <毫秒> / fail <原因>
"""
import json
import sys
import time
import urllib.error
import urllib.request

base, key = sys.argv[1].rstrip("/"), sys.argv[2]
req = urllib.request.Request(base + "/models", headers={"Authorization": f"Bearer {key}"})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        body = json.loads(r.read().decode("utf-8"))
    ms = int((time.time() - t0) * 1000)
    n = len(body.get("data") or [])
    print(f"ok {ms} {n}")
except urllib.error.HTTPError as e:
    print(f"fail HTTP {e.code}")
except Exception as e:
    print(f"fail {type(e).__name__}: {e}")
