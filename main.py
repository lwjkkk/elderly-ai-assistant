import os
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"  # 解决 Windows 下 torch/numpy OpenMP 运行时重复初始化冲突
import torch  # noqa: F401  必须在所有 import 最前：Windows 下晚加载会因 conda 旧 VC++ 运行库
# 导致 torch/lib/shm.dll 加载失败(WinError 127)；进程最早期导入可复用已加载的新版运行库。

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from api.routes import router as chat_router
from api.auth import router as auth_router
from api.bind import router as bind_router
from api.meds import router as meds_router
from api.drugs import router as drugs_router
from api.vitals import router as vitals_router
from api.consults import router as consults_router
from api.symptom import router as symptom_router
from api.reports import router as reports_router
from api.weather import router as weather_router
from api.sync import router as sync_router
from api.privacy import router as privacy_router
from api.users import router as users_router
from db.database import init_db
from services.scheduler import start_scheduler
from config.settings import HOST, PORT


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动：建表 + 启动定时任务
    init_db()
    start_scheduler()
    yield
    # 关闭：定时任务随进程结束


app = FastAPI(title="老年数字辅助智能体后端", lifespan=lifespan)

# 允许前端跨域访问
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(chat_router)    # 原有 /api/chat
app.include_router(auth_router)    # 鉴权 /api/auth
app.include_router(bind_router)    # 绑定 /api/bind
app.include_router(meds_router)    # 用药 /api/meds
app.include_router(drugs_router)   # 查药 /api/drugs
app.include_router(vitals_router)  # 体征 /api/vitals
app.include_router(consults_router)  # 问诊录音 /api/consults
app.include_router(symptom_router)  # 症状自查 /api/symptom-check
app.include_router(reports_router)  # 体检报告 /api/reports
app.include_router(weather_router)  # 天气 /api/weather
app.include_router(sync_router)     # 增量同步 /api/sync
app.include_router(privacy_router)  # 隐私开关 /api/privacy
app.include_router(users_router)    # 用户资料 /api/users


@app.get("/")
def read_root():
    return {"message": "老年数字辅助智能体后端运行正常"}


if __name__ == "__main__":
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)
