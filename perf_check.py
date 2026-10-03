# 简单压测脚本：对只读、不依赖大模型的接口做并发压测
# 用法：python perf_check.py            （默认每接口 50 并发请求）
#       python perf_check.py 100        （自定义请求数）

import sys
import time
import statistics
from concurrent.futures import ThreadPoolExecutor

from fastapi.testclient import TestClient
from main import app

c = TestClient(app)

# 登录拿老人 token
r = c.post("/api/auth/login", json={"phone": "13800000001", "password": "123456"})
TOKEN = r.json()["access_token"]
H = {"Authorization": f"Bearer {TOKEN}"}

# 被测的轻量只读接口（避开 OCR / LLM 等重接口）
ENDPOINTS = [
    ("药品列表", "/api/meds"),
    ("今日用药", "/api/meds/today"),
    ("体征列表", "/api/vitals"),
    ("体征趋势", "/api/vitals/trend"),
    ("增量同步", "/api/sync"),
]

TOTAL = int(sys.argv[1]) if len(sys.argv) > 1 else 50
WORKERS = 10


def one_call(path):
    t0 = time.perf_counter()
    resp = c.get(path, headers=H)
    return resp.status_code, (time.perf_counter() - t0) * 1000  # ms


print(f"每接口 {TOTAL} 请求，并发 {WORKERS}\n")
summary = []
for name, path in ENDPOINTS:
    lat = []
    ok = 0
    wall0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for code, ms in pool.map(lambda _: one_call(path), range(TOTAL)):
            lat.append(ms)
            if code == 200:
                ok += 1
    wall = time.perf_counter() - wall0

    lat_sorted = sorted(lat)
    p95 = lat_sorted[int(len(lat_sorted) * 0.95) - 1]
    qps = TOTAL / wall
    summary.append((name, ok, TOTAL, statistics.mean(lat), p95, qps))
    print(f"{name:<6} 成功 {ok}/{TOTAL} | 平均 {statistics.mean(lat):6.1f}ms "
          f"| P95 {p95:6.1f}ms | {qps:6.1f} QPS")

print("\n判定：全部 200 且 P95 < 500ms 视为本地原型达标。")
