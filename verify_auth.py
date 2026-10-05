# 越权与认证测试：验证 4 类场景
#   1) 未登录调用需要认证的接口 → 401
#   2) 家属调用老人专属接口 → 403
#   3) 未绑定家属查看老人数据 → 403
#   4) 数据隔离：A 老人不能看 B 老人的数据

import random

from fastapi.testclient import TestClient

from db.database import init_db
from main import app

init_db()
client = TestClient(app)

passed = 0
failed = 0


def check(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  [PASS] {name}")
    else:
        failed += 1
        print(f"  [FAIL] {name} {detail}")


# 注册两个老人 + 一个家属（不绑定）
p1 = f"13{random.randint(0, 999999999):09d}"
p2 = f"13{random.randint(0, 999999999):09d}"
pf = f"13{random.randint(0, 999999999):09d}"

for p, role, nick in [(p1, "elder", "老人A"), (p2, "elder", "老人B"), (pf, "family", "家属X")]:
    assert client.post("/api/auth/register", json={"phone": p, "password": "123456", "nickname": nick, "role": role}).status_code == 201

t1 = client.post("/api/auth/login", json={"phone": p1, "password": "123456"}).json()["access_token"]
t2 = client.post("/api/auth/login", json={"phone": p2, "password": "123456"}).json()["access_token"]
tf = client.post("/api/auth/login", json={"phone": pf, "password": "123456"}).json()["access_token"]

h1 = {"Authorization": f"Bearer {t1}"}
h2 = {"Authorization": f"Bearer {t2}"}
hf = {"Authorization": f"Bearer {tf}"}

print("=" * 60)
print("越权与认证测试")
print("=" * 60)

# ---------- 场景1：未登录调用需要认证的接口 → 401 ----------
print("\n[场景1] 未登录调用需要认证的接口")
r = client.get("/api/vitals")
check("未登录查体征 → 401", r.status_code == 401, f"实际 {r.status_code}")

r = client.get("/api/meds/today")
check("未登录查用药 → 401", r.status_code == 401, f"实际 {r.status_code}")

r = client.post("/api/vitals", json={"type": "bp", "systolic": 120, "diastolic": 80})
check("未登录录体征 → 401", r.status_code == 401, f"实际 {r.status_code}")

# ---------- 场景2：家属调用老人专属接口 → 403 ----------
print("\n[场景2] 家属调用老人专属接口")
r = client.put("/api/privacy", json={"sync_summary_to_family": False}, headers=hf)
check("家属改隐私设置 → 403", r.status_code == 403, f"实际 {r.status_code}")

r = client.get("/api/privacy", headers=hf)
check("家属查隐私设置 → 403", r.status_code == 403, f"实际 {r.status_code}")

# ---------- 场景3：未绑定家属查看老人数据 → 403 ----------
print("\n[场景3] 未绑定家属查看老人数据")
# 先让老人A录一条体征
client.post("/api/vitals", json={"type": "bp", "systolic": 130, "diastolic": 85}, headers=h1)

# 家属X（未绑定）指定查看老人A的体征 → 应该403
from db.database import get_db
from db.models import User
db = next(get_db())
elder_a_id = db.query(User).filter(User.phone == p1).first().id
db.close()

r = client.get(f"/api/vitals?elder_id={elder_a_id}", headers=hf)
check("未绑定家属查老人体征 → 403", r.status_code == 403, f"实际 {r.status_code}")

r = client.get(f"/api/meds/today?elder_id={elder_a_id}", headers=hf)
check("未绑定家属查老人用药 → 403", r.status_code == 403, f"实际 {r.status_code}")

# ---------- 场景4：数据隔离：A 老人不能看 B 老人的数据 ----------
print("\n[场景4] 数据隔离：A老人不能看B老人的数据")
# 老人B录一条体征
client.post("/api/vitals", json={"type": "bs", "value": 6.5}, headers=h2)

# 老人A查自己的体征 → 应该只有自己的（bp），没有B的（bs）
r = client.get("/api/vitals", headers=h1)
if r.status_code == 200:
    data = r.json()
    types = [item.get("type") for item in data]
    check("A老人只能看到自己的bp记录", "bp" in types and "bs" not in types, f"实际类型: {types}")
else:
    check("A老人查自己体征 → 200", False, f"实际 {r.status_code}")

# 老人A不能通过 elder_id 看老人B的数据（如果接口支持指定elder_id的话）
# 大部分接口老人只能看自己的，指定其他elder_id会被忽略或返回空

# ---------- 汇总 ----------
print("\n" + "=" * 60)
print(f"越权测试汇总：{passed}/{passed + failed} 通过，{failed} 失败")
if failed > 0:
    print("\n⚠️  存在越权漏洞，需要记录到 Bug 表！")
else:
    print("\n✅ 所有越权场景均正确拦截，无越权漏洞")
print("=" * 60)
