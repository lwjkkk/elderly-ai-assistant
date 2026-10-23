# -*- coding: utf-8 -*-
"""
10.20 紧急症状聊天告警：老人在问答中说出胸痛/呼吸困难/意识异常/中风征象/大出血等
红旗症状时，主动给授权家属发一条红色告警消息，不依赖体征录入阈值。

规则：
- 检测：复用 tiered_answer._EMERGENCY_PATTERNS，在老人提问文本上命中即触发；
- 权限：与读取端一致，senior 强制推家属；younger 按 sync_summary_to_family；unknown 不推；
- 不重复：同一老人 5 分钟内同类紧急问题只推一次（避免连续追问刷消息）；
- 推送：FamilyMessage(kind="emergency_alert") 持久化 + push_svc.send_push 内存日志；
- 不替代诊断：消息内容提示"请立即联系老人或拨打120"，不给处置建议。
"""
from __future__ import annotations

import logging
import re
import threading
import hashlib
from datetime import datetime, timedelta

from core.tiered_answer import _EMERGENCY_PATTERNS, _EMERGENCY_SEEK_PREFIX
from core import age as age_mod
from services import push as push_svc

logger = logging.getLogger(__name__)

# 类别 → 中文标签（用于消息内容和前端分类）
_EMERGENCY_LABELS = [
    ("choking", re.compile(r"噎住|卡喉"), "噎食/气道梗阻"),
    ("chest_pain", re.compile(r"胸痛|胸口压(榨|抑)|心口痛|胸口闷(痛)?|胸闷|胸口疼|心口疼|胸口痛|胸口难受"), "胸痛胸闷"),
    ("breath", re.compile(r"呼吸困难|喘不上气|喘不过气|窒息感|喘不上来|喘不上"), "呼吸困难"),
    ("consciousness", re.compile(r"意识(模糊|不清|丧失)|昏迷|叫不醒|突然晕倒"), "意识不清"),
    ("stroke", re.compile(r"口角歪斜|嘴歪|一侧(肢体|手|脚)(麻木|无力|不能动)|说话(不清|含糊)|吐字不清"), "中风征象"),
    ("bleeding", re.compile(r"大?出血|呕血|咯血|便血|黑便"), "出血"),
]

# 5 分钟内同一老人同类紧急问题不重复推送
_last_notify: dict[int, datetime] = {}
_DEDUP_WINDOW = timedelta(minutes=5)


def detect_emergency(text: str) -> list[str]:
    """返回命中的紧急类别 key 列表（chest_pain/breath/consciousness/stroke/bleeding）。

    两级判断：
    1. 正则关键词命中 → 直接返回（确定急症词，快）；
    2. 正则未命中 → 调 Qwen LLM 二次判断语义，识别"心脏不舒服""喘得厉害"等口语化急症。
    LLM 判断失败时保守返回空（不误报）。
    """
    if not text:
        return []
    hits = []
    for key, pat, _label in _EMERGENCY_LABELS:
        if pat.search(text):
            hits.append(key)
    if hits:
        return hits
    # 正则未命中，走 LLM 语义判断
    try:
        return _llm_judge_emergency(text)
    except Exception as e:
        logger.warning(f"紧急告警 LLM 判断失败，保守不告警：{e}")
        return []


def _llm_judge_emergency(text: str) -> list[str]:
    """用 Qwen 判断用户这句话是否描述了需要立即就医/拨打120的急症症状。

    返回紧急类别 key 列表；无法判断时返回空。
    """
    import json
    from core.qwen_llm import call_qwen

    system = (
        "你是急症分诊助手。判断用户的这句话是否描述了需要立即就医或拨打120的急症症状。"
        "只输出 JSON，不要多余文字。格式："
        '{"emergency": true/false, "types": ["chest_pain"|"breath"|"consciousness"|"stroke"|"bleeding"], "reason": "简短原因"}\n'
        "类别说明：\n"
        "- chest_pain：胸痛、胸闷、心口压迫感、心脏不舒服伴疼痛/压榨感\n"
        "- breath：呼吸困难、喘不上气、上不来气、窒息感\n"
        "- consciousness：意识模糊、昏迷、叫不醒、晕倒\n"
        "- stroke：口角歪斜、一侧肢体麻木无力、说话不清\n"
        "- bleeding：呕血、咯血、便血、大量出血\n"
        "普通咨询（如'高血压怎么控制''感冒吃什么药'）emergency=false。"
    )
    out = call_qwen(system, f"用户说：{text}")
    # 提取 JSON
    m = re.search(r"\{.*\}", out, re.S)
    if not m:
        return []
    try:
        data = json.loads(m.group(0))
    except Exception:
        return []
    if not data.get("emergency"):
        return []
    types = data.get("types") or []
    valid = {"chest_pain", "breath", "consciousness", "stroke", "bleeding", "choking"}
    return [t for t in types if t in valid]


def _labels_for(keys: list[str]) -> list[str]:
    return [label for k, _, label in _EMERGENCY_LABELS if k in keys]


def notify_family_async(db_session_factory, elder_user, question: str, types: list[str]) -> threading.Thread:
    """后台线程：给授权绑定家属写紧急告警消息。
    db_session_factory 是 SessionLocal，在线程内新建 session（不能跨线程复用请求 session）。
    """
    elder_id = elder_user.id
    def _run():
        try:
            db = db_session_factory()
            try:
                # 请求结束后 ORM 对象可能已失效，且用户可能已撤回共享；在线程内重新读取。
                from db.models import User
                elder_user = db.get(User, elder_id)
                if elder_user is None:
                    return
                # 去重
                now = datetime.now()
                last = _last_notify.get(elder_user.id)
                if last and (now - last) < _DEDUP_WINDOW:
                    logger.info(f"紧急告警去重：elder={elder_user.id} 5分钟内已推过")
                    return
                _last_notify[elder_user.id] = now

                # 权限闸门：与读取端一致
                tier = age_mod.age_tier(elder_user.birth_ym)
                if tier == age_mod.TIER_UNKNOWN:
                    logger.info(f"紧急告警：elder={elder_user.id} birth_ym 缺失，不推家属")
                    return
                if tier == age_mod.TIER_YOUNGER and elder_user.sync_summary_to_family is False:
                    logger.info(f"紧急告警：elder={elder_user.id} 未满60关闭分享，不推家属")
                    return

                from db.models import FamilyBinding
                bindings = (
                    db.query(FamilyBinding)
                    .filter(FamilyBinding.elder_id == elder_user.id,
                            FamilyBinding.status == "active",
                            FamilyBinding.family_id.isnot(None))
                    .all()
                )
                if not bindings:
                    return

                labels = "、".join(_labels_for(types))
                content = {
                    "type": "emergency_chat",
                    "origin": "system",
                    "elder_id": elder_user.id,
                    "emergency_types": types,
                    "emergency_labels": labels,
                    "question": question[:200],
                    "advice": "老人可能出现紧急症状，请立即联系老人或拨打120/前往急诊。",
                    "seek_prefix": _EMERGENCY_SEEK_PREFIX,
                }
                for b in bindings:
                    from db.models import FamilyMessage, NotificationOutbox
                    db.add(FamilyMessage(
                        binding_id=b.id,
                        sender_id=elder_user.id,
                        kind="emergency_alert",
                        content=content,
                    ))
                    time_bucket = int(now.timestamp() // 300)
                    fingerprint = hashlib.sha256(
                        f"{elder_user.id}|{time_bucket}|{','.join(types)}|{question[:200]}".encode("utf-8")
                    ).hexdigest()[:24]
                    db.add(NotificationOutbox(
                        elder_id=elder_user.id, receiver_id=b.family_id,
                        channel="in_app" if push_svc.adapter_name() == "memory" else "push",
                        status="pending", title="紧急情况提醒",
                        content=f"老人提到{labels}，请立即联系老人或拨打120。",
                        dedupe_key=f"emergency:{fingerprint}:family:{b.family_id}",
                    ))
                db.commit()
                from services.notification_outbox import process_pending
                process_pending(db_session_factory)
                logger.info(f"紧急告警已推送给 {len(bindings)} 位家属：elder={elder_user.id} types={types}")
            finally:
                db.close()
        except Exception:
            logger.exception("紧急告警后台推送失败")

    worker = threading.Thread(target=_run, daemon=True)
    worker.start()
    return worker
