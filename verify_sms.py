# 验证码登录（控制台打印模式）验证脚本
# 依赖 TestClient，模拟真实 HTTP 调用，验证 4 个关键行为：
#   1) 取验证码成功且接口不返回 code
#   2) 用错误验证码登录被拒
#   3) 用正确验证码登录成功，返回 JWT
#   4) 验证码一次性：登录成功后再次使用被拒

import random

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)

# 用随机手机号避免与已有数据冲突
phone = f"13{random.randint(0, 999999999):09d}"


def show(title, resp):
    print(f"[{title}] status={resp.status_code} body={resp.json()}")


def main():
    # 0) 先注册一个账号，才能验证码登录
    reg = client.post("/api/auth/register", json={
        "phone": phone, "password": "123456",
        "nickname": "测试老人", "role": "elder",
    })
    show("注册", reg)

    # 1) 取验证码
    sms = client.post("/api/auth/send_sms_code", json={"phone": phone})
    show("取验证码", sms)
    assert sms.status_code == 200, "取验证码失败"
    body = sms.json()
    # 接口绝不能把验证码数字返回给前端
    assert "code" not in body, "接口不应返回验证码本体"
    print("      -> 返回体中没有 code 字段，符合演示安全预期（验证码只在控制台打印）")

    # 2) 错误验证码登录
    bad = client.post("/api/auth/login_by_code", json={"phone": phone, "code": "000000"})
    show("错误验证码登录", bad)
    assert bad.status_code == 401, "错误验证码应被拒绝"

    # 3) 正确验证码登录：从内存存储里读出真实码来模拟“用户在控制台看到后输入”
    from api.auth import _sms_codes, SMS_CODE_EXPIRE_SECONDS
    real_code = _sms_codes[phone]["code"]
    print(f"      -> 控制台打印的验证码为: {real_code}（真实短信应通过用户手机收到）")

    good = client.post("/api/auth/login_by_code", json={"phone": phone, "code": real_code})
    show("正确验证码登录", good)
    assert good.status_code == 200, "正确验证码应登录成功"
    assert good.json().get("access_token"), "应返回 access_token"

    # 4) 验证码一次性
    reuse = client.post("/api/auth/login_by_code", json={"phone": phone, "code": real_code})
    show("复用同一验证码", reuse)
    assert reuse.status_code in (400, 401), "复用验证码应被拒绝"

    print("\n✅ 验证码登录四项全部通过：取码不回传→错码拒绝→对码登录→一次性作废")


if __name__ == "__main__":
    main()
