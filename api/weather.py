# 天气提醒接口：返回今日天气与给老人的弹窗提醒

from fastapi import APIRouter, Depends

from db.models import User
from db.schemas import WeatherRemind
from core.security import get_current_user
from services.weather import get_weather_remind

router = APIRouter(prefix="/api/weather", tags=["天气"])


@router.get("/remind", response_model=WeatherRemind)
def remind(city: str | None = None,
           lat: float | None = None,
           lon: float | None = None,
           current: User = Depends(get_current_user)):
    """天气提醒。App 自动定位后传 lat/lat（纬度）、lon（经度），精确到区县；
    不传则用后端默认位置，老人无需手动输入。"""
    data = get_weather_remind(city, lat, lon)
    return WeatherRemind(
        city=data["city"],
        text=data["text"],
        tip=data["tip"],
        warning=data["warning"],
    )
