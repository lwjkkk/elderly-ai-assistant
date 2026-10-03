# 天气服务：封装和风天气 API，生成给老人的弹窗提醒
# 未配置 key 或请求失败时优雅降级，返回提示而不是抛错。

import os

import httpx
from dotenv import load_dotenv

load_dotenv()  # 确保 .env 中的 QWEATHER_API_KEY 生效


def _build_tip(today: dict) -> tuple[str, str | None]:
    """根据今日预报生成提醒文案和预警信息。"""
    text_day = today.get("textDay", "")
    temp_max = int(today.get("tempMax", 20))
    temp_min = int(today.get("tempMin", 20))

    tips = []
    warning = None

    if "雪" in text_day:
        tips.append("今天有雪，出门注意防滑保暖，尽量有人陪同")
        warning = text_day
    elif "雨" in text_day:
        tips.append("今天有雨，记得带伞，路面湿滑慢走")
        warning = text_day
    elif "暴雨" in text_day or "台风" in text_day:
        tips.append("天气恶劣，建议今天尽量不要出门")
        warning = text_day

    if temp_max >= 35:
        tips.append("气温高，注意防暑、多喝水，避开正午外出")
        warning = warning or "高温"
    if temp_min <= 5:
        tips.append("天气寒冷，注意添衣保暖，小心心脑血管受凉")
    if temp_max - temp_min >= 10:
        tips.append("昼夜温差大，出门随身带件外套，及时增减衣物")

    if not tips:
        tips.append("天气不错，适合正常活动和适度锻炼")

    return "；".join(tips), warning


def get_weather_remind(city: str | None = None,
                       lat: float | None = None,
                       lon: float | None = None) -> dict:
    """查询天气并生成提醒。返回 city/text/tip/warning/configured。
    优先用前端传入的 GPS 经纬度（精确到区县、老人无需输入）；
    没传则用 .env 的 DEFAULT_LOCATION。走专属 Host + X-QW-Api-Key 请求头。"""
    key = os.getenv("QWEATHER_API_KEY", "")
    api_host = os.getenv("QWEATHER_API_HOST", "").strip().rstrip("/")

    # 经纬度格式为 经度,纬度（longitude,latitude）
    if lat is not None and lon is not None:
        location = f"{lon},{lat}"
    else:
        # 默认：丽水莲都 119.92,28.45
        location = os.getenv("DEFAULT_LOCATION", "119.92,28.45")
    city_name = city or os.getenv("DEFAULT_CITY", "丽水")

    if not key or not api_host:
        return {
            "city": city_name, "text": "天气服务未配置",
            "tip": "请在 .env 配置 QWEATHER_API_KEY、QWEATHER_API_HOST（控制台设置中查看）",
            "warning": None, "configured": False,
        }

    try:
        headers = {"X-QW-Api-Key": key}
        with httpx.Client(trust_env=False, timeout=10, headers=headers) as cx:
            weather = cx.get(f"{api_host}/v7/weather/3d",
                             params={"location": location}).json()
            today = weather["daily"][0]

        text = f"{today['textDay']} {today['tempMin']}~{today['tempMax']}℃"
        tip, warning = _build_tip(today)
        return {"city": city_name, "text": text, "tip": tip,
                "warning": warning, "configured": True}

    except Exception as e:
        return {
            "city": city_name, "text": "天气获取失败",
            "tip": f"暂时无法获取天气，请稍后再试（{e}）",
            "warning": None, "configured": False,
        }
