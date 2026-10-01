# 推送服务（抽象层）
# 当前默认实现：把通知记录到日志和内存列表，便于本地演示与测试。
# 接入真实 App 后，只需在 send_push 内替换为 JPush / 厂商通道（华为、小米、苹果 APNs）调用。

import logging

logger = logging.getLogger(__name__)

# 本地记录已发送通知（重启清空，仅用于演示/测试）
_sent: list[dict] = []


def send_push(receiver_id: int, title: str, content: str) -> dict:
    """向指定用户推送一条通知。返回通知内容。"""
    note = {"receiver_id": receiver_id, "title": title, "content": content}
    _sent.append(note)
    logger.info("推送 -> 用户%s | %s | %s", receiver_id, title, content)
    # TODO: 接入真实推送时在此调用 JPush / APNs / 厂商 HTTP API
    return note


def get_sent() -> list[dict]:
    """读取已发送通知（测试用）。"""
    return list(_sent)


def clear_sent() -> None:
    """清空记录（测试用）。"""
    _sent.clear()
