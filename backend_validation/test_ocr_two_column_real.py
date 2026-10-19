# -*- coding: utf-8 -*-
"""真实双栏体检单（用户提供）OCR 端到端 + 解析验证。
走 图片→recognize_image(坐标重建双栏)→parse_metrics 完整链路。
用“值+判定”断言（OCR 对部分指标名有截断/拆行，但值必须准确）。
运行：D:\\python\\python.exe -X utf8 backend_validation\\test_ocr_two_column_real.py
（首次自动加载已缓存模型，约 15~20s）
"""
import os
import sys
import base64
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
IMG = os.path.join(HERE, "sample_report_real.png")

# 期望命中：{中文名: (真实值, 判定)}。判定取值 normal/high/low。
# 依据原图人工核对；仅断言"值在正确指标上被解析出且判定正确"。
EXPECT = {
    "钾离子": (4.60, "normal"), "钠离子": (140, "normal"), "氯离子": (108, "normal"),
    "碳酸氢根": (31.4, "high"), "钙离子": (2.39, "normal"), "血清磷": (1.39, "normal"),
    "血清镁": (0.84, "normal"), "葡萄糖": (4.92, "normal"), "尿素氮": (2.84, "normal"),
    "肌酐": (75.4, "normal"), "尿酸": (301.6, "normal"), "甘油三酯": (0.53, "normal"),
    "总胆固醇": (2.64, "low"), "高密度脂蛋白胆固醇": (1.33, "normal"),
    "低密度脂蛋白胆固醇": (1.21, "normal"), "载脂蛋白A1": (1.11, "normal"),
    "谷丙转氨酶": (14.4, "normal"), "谷草转氨酶": (19.5, "normal"),
    "碱性磷酸酶": (53.8, "normal"), "谷氨酰转肽酶": (16.0, "normal"),
    "乳酸脱氢酶": (132.9, "normal"), "总胆红素": (22.7, "high"),
    "直接胆红素": (8.8, "high"), "间接胆红素": (13.9, "normal"),
    "总蛋白": (70.5, "normal"), "白蛋白": (48.9, "normal"), "球蛋白": (21.6, "normal"),
    "白球比": (2.26, "normal"), "淀粉酶": (53.0, "normal"), "前白蛋白": (192.5, "low"),
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
            code = (m.get("code") or "").replace(" ", "")
            for a in aliases:
                if a in code:
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
        # 值+判定双命中 >= 22（允许少量名称/拆分未配对的指标）
        self.assertGreaterEqual(hits, 22,
                                "真实双栏单值+判定命中不足：%d/%d" % (hits, len(EXPECT)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
