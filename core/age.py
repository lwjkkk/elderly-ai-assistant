# -*- coding: utf-8 -*-
"""
10.26 #5 年龄分层——年龄计算与 60 岁分层规则。

规则（依据计划 #5 与团队讨论）：
- 满 60 周岁及以上（senior）：强制把对话摘要/查药记录分享给绑定子女，无隐私关闭按钮，
  隐私开关被锁定为“开启分享”（sync_summary_to_family 恒为 True），且清空隐私开启时间。
- 未满 60 周岁（younger）：保留老人自行选择隐私开关的权利（可选分享）。
- 未设置出生年月或出生年月无效（unknown）：按 younger 处理（不强制），提示补齐资料。

年龄口径：birth_ym 为 YYYY-MM，按参考日期（默认今天）计算周岁；
满 60 岁判定取“出生月 ≤ 当前月”为已过生日（60 岁整即算 senior）。
"""
import re
from datetime import date, datetime
from zoneinfo import ZoneInfo

_BIRTH_YM_RE = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])$")
SENIOR_AGE = 60
TIER_SENIOR = "senior"     # 满 60 周岁及以上：强制分享
TIER_YOUNGER = "younger"   # 未满 60 周岁：可选分享
TIER_UNKNOWN = "unknown"   # 未设置/无效出生年月：不强制，提示补齐


def parse_birth_ym(birth_ym: str | None) -> tuple[int, int] | None:
    """解析 YYYY-MM → (年, 月)；无效返回 None。"""
    if not birth_ym:
        return None
    m = _BIRTH_YM_RE.match(str(birth_ym).strip())
    if not m:
        return None
    year, month = int(m.group(1)), int(m.group(2))
    if year < 1900 or (year, month) > (datetime.now(ZoneInfo("Asia/Shanghai")).year,
                                        datetime.now(ZoneInfo("Asia/Shanghai")).month):
        return None
    return year, month


def compute_age(birth_ym: str | None, ref_date: date | None = None) -> int | None:
    """
    按出生年月计算周岁。取“出生月 ≤ 参考月”为当年已过生日，返回整周岁。
    未设置/无效返回 None；参考日期早于出生年月（未来出生）返回 None。
    """
    ym = parse_birth_ym(birth_ym)
    if not ym:
        return None
    ref = ref_date or datetime.now(ZoneInfo("Asia/Shanghai")).date()
    by, bm = ym
    if (by, bm) > (ref.year, ref.month):
        return None  # 出生年月在未来，资料异常
    age = ref.year - by
    if bm > ref.month:
        age -= 1
    return max(age, 0)


def age_tier(birth_ym: str | None, ref_date: date | None = None) -> str:
    """按年龄返回分层：senior / younger / unknown。"""
    age = compute_age(birth_ym, ref_date)
    if age is None:
        return TIER_UNKNOWN
    return TIER_SENIOR if age >= SENIOR_AGE else TIER_YOUNGER


def is_senior(birth_ym: str | None, ref_date: date | None = None) -> bool:
    return age_tier(birth_ym, ref_date) == TIER_SENIOR


def tier_meta(tier: str) -> dict:
    """分层规则的机器可读说明，供前端展示入口与共享说明。"""
    return {
        "tier": tier,
        "label": {
            TIER_SENIOR: "满60周岁及以上",
            TIER_YOUNGER: "未满60周岁",
            TIER_UNKNOWN: "未设置出生年月",
        }[tier],
        "share_policy": {
            TIER_SENIOR: "强制分享给子女，无隐私关闭按钮",
            TIER_YOUNGER: "可选分享，保留隐私开关",
            TIER_UNKNOWN: "默认可选分享，请补齐出生年月以启用分层",
        }[tier],
    }


def enforce_senior_share(db, user) -> bool:
    """
    强制分享策略落库：若用户为 senior 且当前 sync_summary_to_family 为 False，
    置为 True 并清空 privacy_enabled_at（家属可看全部历史）。
    返回是否发生了强制改写。senior 之外一律不强制。
    """
    if not is_senior(user.birth_ym):
        return False
    if user.sync_summary_to_family is False:
        user.sync_summary_to_family = True
        user.privacy_enabled_at = None
        db.commit()
        return True
    return False


def forced_share(birth_ym: str | None) -> bool:
    """该出生年月是否处于强制分享分层（供接口返回给前端隐藏关闭按钮）。"""
    return is_senior(birth_ym)


# ---------- 家属读取健康资料的统一权限闸门 ----------
# 规则（按计划 #5/#18）：
#   1) 家属本人访问自己数据：放行；
#   2) 无 active 绑定：拒绝；
#   3) 老人出生年月缺失：拒绝，要求补全资料后再开放；
#   4) 满 60 周岁（senior）：强制分享，无视旧 sync_summary_to_family=False；
#   5) 未满 60（younger）：按老人隐私开关 sync_summary_to_family 判断；
#   6) unknown（出生年月无效）：按 younger 处理，但返回 reason=birth_missing 提示补全。
# 每次家属读取/同步都实时调用，不依赖数据库旧开关值是否已被回填。

def family_access_guard(db, family_user, elder_user) -> tuple[bool, str]:
    """
    返回 (allowed, reason)。
    reason: ok / not_binding / birth_missing / privacy_off / not_elder / elder_not_found
    """
    if elder_user is None:
        return False, "elder_not_found"
    if family_user.id == elder_user.id:
        return True, "ok"
    if family_user.role != "family" or elder_user.role != "elder":
        return False, "not_elder"
    from db.models import FamilyBinding
    binding = (db.query(FamilyBinding)
               .filter(FamilyBinding.elder_id == elder_user.id,
                       FamilyBinding.family_id == family_user.id,
                       FamilyBinding.status == "active")
               .first())
    if not binding:
        return False, "not_binding"
    # 实时落库 senior 强制分享（旧库 sync_summary_to_family=False 被纠正）
    enforce_senior_share(db, elder_user)
    tier = age_tier(elder_user.birth_ym)
    if tier == TIER_UNKNOWN:
        return False, "birth_missing"
    if tier == TIER_SENIOR:
        return True, "ok"
    # younger：按隐私开关
    if elder_user.sync_summary_to_family is False:
        return False, "privacy_off"
    return True, "ok"

