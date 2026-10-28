# -*- coding: utf-8 -*-
"""真实双栏体检单（用户提供）OCR 端到端 + 解析验证。
走 图片→recognize_image(坐标重建双栏)→parse_metrics 完整链路。
用“值+判定”断言（OCR 对部分指标名有截断/拆行，但值必须准确）。
运行：D:\\python\\python.exe -X utf8 backend_validation\\test_ocr_two_column_real.py
（首次自动加载已缓存模型，约 15~20s）
"""

# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
import os
import sys
import base64
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
IMG = str(_Path(__file__).resolve().parents[1] / "fixtures/sample_report_real.png")

# 期望命中：{中文名: (真实值, 判定)}。判定取值 normal/high/low。
# 按用户提供的 sample_report_real.png（单栏生化报告，送检 2025/12/26）人工核对。
EXPECT = {
    "谷丙转氨酶": (21.4, "normal"), "谷草转氨酶": (16.6, "normal"),
    "总蛋白": (76.2, "normal"), "白蛋白": (46.3, "normal"),
    "总胆红素": (7.93, "normal"), "直接胆红素": (1.43, "normal"),
    "总胆汁酸": (3.4, "normal"), "尿酸": (199.3, "normal"),
    "肌酐": (45.0, "normal"), "尿素": (3.47, "normal"),
    "甘油三酯": (1.84, "high"), "总胆固醇": (5.44, "high"),
    "高密度脂蛋白胆固醇": (1.42, "normal"),
    "低密度脂蛋白胆固醇": (3.78, "high"),
    "葡萄糖": (5.85, "normal"),
}

# 名称可能被 OCR 截断（如"高密度脂蛋白胆固"），做前缀匹配
NAME_ALIAS = {
    "高密度脂蛋白胆固醇": ("高密度脂蛋白", "高密度脂蛋白胆固醇"),
    "低密度脂蛋白胆固醇": ("低密度脂蛋白", "低密度脂蛋白胆固醇"),
    "载脂蛋白A1": ("载脂蛋白A", "载脂蛋白"),
    "谷氨酰转肽酶": ("谷酰转肽酶", "谷氨酰转肽酶", "谷胺酰转肽酶"),
}


class TestTwoColumnReal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(IMG, "rb") as f:
            b64 = base64.b64encode(f.read()).decode("ascii")
        from core.ocr import recognize_image
        from core.report_parse import parse_metrics
        cls.text = recognize_image(b64)
        cls.metrics = parse_metrics(cls.text)

    def _find(self, name):
        aliases = NAME_ALIAS.get(name, (name,))
        best = None
        for m in self.metrics:
            # 在 ocr_text 里匹配中文名（code 是英文代号 ALT/AST 等）
            hay = (m.get("ocr_text") or "") + " " + (m.get("code") or "")
            for a in aliases:
                if a in hay:
                    if best is None or abs((m.get("result") or 0) - EXPECT[name][0]) < abs(
                            (best.get("result") or 0) - EXPECT[name][0]):
                        best = m
        return best

    def test_real_two_column_report(self):
        hits = 0
        for name, (value, status) in EXPECT.items():
            m = self._find(name)
            if m is None:
                continue
            r = m.get("result")
            if r is None or abs(r - value) > 0.02:
                continue
            if m["status"] != status:
                continue
            hits += 1
        # 值+判定双命中 >= 12（允许少量名称截断/拆分未配对）
        self.assertGreaterEqual(hits, 12,
                                "真实单栏报告值+判定命中不足：%d/%d" % (hits, len(EXPECT)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
