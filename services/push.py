# -*- coding: utf-8 -*-
"""
推送服务（可插拔适配器层）。

说明（10.28 增强）：
- 默认使用 MemoryPushAdapter：把通知写入内存列表并打日志，可本地演示、可真实测试（send_push -> get_sent）。
- 真实手机推送无法只靠"下载依赖"完成，还依赖两类不可下载的东西：
  1) 推送服务账号凭证（app_key/master_secret / 厂商 / FCM 凭据，需注册开通）；
  2) 前端 App 集成 SDK 后上报的设备 token（后端需有真实设备目标）。
  因此 RealPushAdapter 在缺少凭证时明确报错、绝不假装已发送；凭证与设备 token 到位后，
  经 set_adapter(RealPushAdapter(...)) 切换并做冒烟。当前默认内存适配器，保持既有调用不变。
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


class PushAdapter:
    """推送通道抽象基类。子类实现 send；缺凭证/未接入时须明确报错，不得静默降级。"""
    name = "base"

    def send(self, receiver_id: int, title: str, content: str) -> dict:
        raise NotImplementedError


class MemoryPushAdapter(PushAdapter):
    """默认适配器：通知写入内存列表 + 日志，重启清空。本地演示与测试用。"""
    name = "memory"
    _sent: list[dict] = []

    def send(self, receiver_id: int, title: str, content: str) -> dict:
        note = {"receiver_id": receiver_id, "title": title, "content": content}
        self._sent.append(note)
        logger.info("推送 -> 用户%s | %s | %s", receiver_id, title, content)
        return note

    def get_sent(self) -> list[dict]:
        return list(self._sent)

    def clear(self) -> None:
        self._sent.clear()


class RealPushAdapter(PushAdapter):
    """真实手机推送通道（预留接入骨架）。

    构造或 send 时缺少凭证/设备 token 会明确报错，绝不假装已发送。
    接入步骤：提供推送服务凭证(app_key/master_secret/厂商或FCM凭据)、前端上报的设备 token 注册表，
    再在此 send 内调用真实 HTTP 推送端点并做冒烟测试。
    """
    name = "real"

    def __init__(self, app_key: str | None = None, master_secret: str | None = None,
                 device_tokens: list[str] | None = None):
        self._app_key = app_key
        self._master_secret = master_secret
        self._device_tokens = device_tokens or []

    @property
    def _ready(self) -> bool:
        return bool(self._app_key and self._master_secret and self._device_tokens)

    def send(self, receiver_id: int, title: str, content: str) -> dict:
        if not self._ready:
            raise ValueError(
                "真实推送未就绪：缺少推送服务凭证(app_key/master_secret)或前端上报的设备token，"
                "无法发送真实推送。请接入凭证与设备 token 后再调用。")
        # 接入点：调用 JPush/厂商/FCM 真实 HTTP API 发送到 self._device_tokens
        raise NotImplementedError(
            "真实推送端点待接入：凭证与设备token已齐备后，在此调用推送服务HTTP API并做冒烟。")


# 当前激活适配器（默认内存，可测试；真实凭证到位后 set_adapter 切换）
_active: PushAdapter = MemoryPushAdapter()


def send_push(receiver_id: int, title: str, content: str) -> dict:
    """向指定用户推送一条通知，由当前激活适配器处理。"""
    return _active.send(receiver_id, title, content)


def get_sent() -> list[dict]:
    """读取已发送通知（内存适配器测试用）。"""
    if isinstance(_active, MemoryPushAdapter):
        return _active.get_sent()
    return []


def adapter_name() -> str:
    """Return the active adapter name for truthful persistent delivery status."""
    return _active.name


def capabilities() -> dict:
    """No permission flag, memory record or credentials alone proves phone delivery."""
    if isinstance(_active, MemoryPushAdapter):
        state = "not_configured"
        reason = "当前仅记录通知，未接入真实远程推送服务"
    elif isinstance(_active, RealPushAdapter):
        state = "not_implemented" if _active._ready else "not_configured"
        reason = "真实推送端点尚未接入" if _active._ready else "真实推送服务凭证、设备令牌或发送通道未就绪"
    else:
        state = "unverified"
        reason = "自定义推送通道尚未提供可核验的能力状态"
    return {"adapter": _active.name, "state": state, "ready": False,
            "delivery_guaranteed": False, "reason": reason,
            "recorded_means": "服务端已记录，不代表手机收到通知",
            "submitted_means": "通道已受理，不代表设备已送达"}


def clear_sent() -> None:
    """清空内存记录（测试用）。"""
    if isinstance(_active, MemoryPushAdapter):
        _active.clear()


def set_adapter(adapter: PushAdapter) -> PushAdapter:
    """切换推送通道（真实凭证/设备token到位后切换到 RealPushAdapter）。"""
    global _active
    _active = adapter
    logger.info("推送通道切换为 %s", adapter.name)
    return adapter
