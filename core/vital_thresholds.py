# -*- coding: utf-8 -*-
"""
10.27 #9 体征异常预警：血压/血糖异常阈值判定。

阈值口径（提示性，非诊断）：
- 血压（成人）：收缩压 SBP≥140 mmHg 或 舒张压 DBP≥90 mmHg → 偏高（提示高血压切点，
  参照《中国高血压防治指南（2024年修订版）》，未用药诊室血压≥140/90 为高血压诊断切点；
  家庭血压 ≥135/85）。偏低：SBP<90 或 DBP<60 mmHg → 提示低血压倾向。
- 血糖：空腹血糖 ≥7.0 mmol/L → 偏高（糖尿病诊断切点，中国2型糖尿病防治指南2020 / WS 397-2012）；
  血糖 <3.9 mmol/L → 偏低（低血糖风险提示）。

系统仅做"提示"，不替代诊断：事件 message 统一注明"提示"与"建议规范复测/就医"，
阈值来源由 C 按计划整理主测复核，A 实现可配置常量（改本文件即调整）。
"""
from __future__ import annotations

# ---- 阈值常量（可配置，供 C 复核调整）----
BP_SYS_HIGH = 140      # 收缩压偏高切点 mmHg
BP_DIA_HIGH = 90       # 舒张压偏高切点 mmHg
BP_SYS_LOW = 90        # 收缩压偏低切点 mmHg
BP_DIA_LOW = 60        # 舒张压偏低切点 mmHg
BS_HIGH = 7.0          # 血糖偏高切点 mmol/L（空腹）
BS_LOW = 3.9           # 血糖偏低切点 mmol/L

SOURCE = ("血压：《中国高血压防治指南（2024年修订版）》成人未用药诊室血压≥140/90 mmHg 为高血压诊断切点；"
          "血糖：空腹血糖≥7.0 mmol/L 为糖尿病诊断切点（《中国2型糖尿病防治指南(2020年版)》/WS 397-2012），"
          "低血糖风险 <3.9 mmol/L。系统仅提示，不替代诊断，口径由 C 主测复核。")


def evaluate_bp(systolic: int, diastolic: int) -> dict:
    """血压异常判定。返回 abnormal/level(hight|low|mixed)/message/thresholds/source。"""
    high = systolic >= BP_SYS_HIGH or diastolic >= BP_DIA_HIGH
    low = systolic < BP_SYS_LOW or diastolic < BP_DIA_LOW
    if high and low:
        level, message = "mixed", "血压同时存在偏高与偏低信号（收缩压≥140 或舒张压≥90，且收缩压<90 或舒张压<60），请规范复测并与医生核对"
    elif high:
        level, message = "high", f"血压偏高（{systolic}/{diastolic} mmHg），提示血压≥140/90，建议规范复测并按医嘱处理"
    elif low:
        level, message = "low", f"血压偏低（{systolic}/{diastolic} mmHg），提示收缩压<90 或舒张压<60，请留意头晕等不适并及时就医"
    else:
        level, message = None, "血压在提示阈值内"
    return {
        "abnormal": high or low,
        "level": level,
        "message": message,
        "thresholds": {"systolic_high": BP_SYS_HIGH, "diastolic_high": BP_DIA_HIGH,
                       "systolic_low": BP_SYS_LOW, "diastolic_low": BP_DIA_LOW},
        "source": SOURCE,
    }


def evaluate_bs(value: float, measurement_context: str | None = None) -> dict:
    """血糖异常判定；7.0 高值阈值只适用于明确标注为空腹的读数。"""
    if value >= BS_HIGH and measurement_context == "fasting":
        level, message = "high", f"空腹血糖偏高（{value} mmol/L），提示空腹血糖≥7.0，请复测并结合医生判断"
    elif value >= BS_HIGH:
        level, message = None, "该读数未注明为空腹测量，暂不按空腹血糖阈值触发高值预警"
    elif value < BS_LOW:
        level, message = "low", f"血糖偏低（{value} mmol/L），提示低血糖风险（<3.9），如有心慌出汗请及时处理"
    else:
        level, message = None, "血糖在提示阈值内"
    return {
        "abnormal": level is not None,
        "level": level,
        "message": message,
        "thresholds": {"high": BS_HIGH, "high_context": "fasting", "low": BS_LOW},
        "measurement_context": measurement_context or "unknown",
        "source": SOURCE,
    }


def evaluate(vital_type: str, systolic=None, diastolic=None, value=None,
             measurement_context: str | None = None) -> dict | None:
    """按体征类型返回异常判定；非血压/血糖（心率/体重）不判异常，返回 None。"""
    if vital_type == "bp":
        return evaluate_bp(int(systolic), int(diastolic))
    if vital_type == "bs":
        return evaluate_bs(float(value), measurement_context)
    return None
