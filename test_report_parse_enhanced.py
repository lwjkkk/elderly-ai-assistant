# -*- coding: utf-8 -*-
"""10.21 报告解析增强用例（真实环境运行，无需 OCR 图像依赖）：
覆盖 parse_metrics 新增的 单位解析 / 表头跳过 / 错行合并 / OCR 原文证据字段 / 二次规则校验，
并回归验证旧字段判定结果不变（向后兼容）。"""
import unittest

from core.report_parse import parse_metrics


class ReportParseEnhancedTests(unittest.TestCase):

    def test_unit_parsed_blood_glucose(self):
        # 单位解析：mmol/L
        m = parse_metrics('GLU 7.2 mmol/L 3.9-6.1')[0]
        self.assertEqual(m['status'], 'high')
        self.assertEqual(m['result'], 7.2)
        self.assertEqual(m['unit'], 'mmol/L')

    def test_unit_u_l(self):
        # U/L 单位 + unparsed 兜底（无参考范围）
        m = parse_metrics('ALT 52 U/L')[0]
        self.assertEqual(m['status'], 'unparsed')
        self.assertEqual(m['unit'], 'U/L')

    def test_unit_mmhg(self):
        # 血压单位
        m = parse_metrics('血压 120/80 mmHg')[0]
        self.assertEqual(m['unit'], 'mmHg')

    def test_header_row_skipped(self):
        # 表头行不产生假指标，数据行正常
        ocr = '检查项目\t结果\t单位\t参考范围\n血糖 GLU 5.6 mmol/L 3.9-6.1'
        ms = parse_metrics(ocr)
        self.assertEqual(len(ms), 1)
        self.assertEqual(ms[0]['code'], 'GLU')
        self.assertEqual(ms[0]['status'], 'normal')

    def test_folded_line_merged(self):
        # 错行合并：指标名单独一行 + 数值行 → 合并为一条
        ocr = '总胆固醇\nTC 6.2 mmol/L 2.8-5.2'
        ms = parse_metrics(ocr)
        self.assertEqual(len(ms), 1)
        self.assertEqual(ms[0]['code'], 'TC')
        self.assertEqual(ms[0]['result'], 6.2)
        self.assertEqual(ms[0]['status'], 'high')
        self.assertIn('总胆固醇', ms[0]['ocr_text'])

    def test_evidence_fields(self):
        # OCR 原文证据字段：ocr_text / source_line / range_text
        ocr = '空腹血糖\nGLU 5.1 mmol/L 3.9-6.1'
        ms = parse_metrics(ocr)
        self.assertEqual(len(ms), 1)
        m = ms[0]
        self.assertEqual(m['source_line'], 0)
        self.assertIn('空腹血糖', m['ocr_text'])
        self.assertEqual(m['range_text'], '3.9-6.1')

    def test_second_pass_implausible_glucose(self):
        # 二次校验：51.0 超血糖生理范围 → OCR 错值降级为 unparsed，不当作异常
        m = parse_metrics('GLU 51.0 3.9-6.1')[0]
        self.assertEqual(m['status'], 'unparsed')

    def test_backward_compat_reference_separators(self):
        # 向后兼容：原有范围分隔符判定不变
        for sep in ['--', '~', '～', '至', '-']:
            row = parse_metrics(f'GLU 7.2 mmol/L 3,9{sep}6. 1')[0]
            self.assertEqual((row['lo'], row['hi'], row['status']), (3.9, 6.1, 'high'))

    def test_backward_compat_unparsed(self):
        # 向后兼容：ALT 52 U/L 仍为 unparsed
        self.assertEqual(parse_metrics('ALT 52 U/L')[0]['status'], 'unparsed')

    def test_multiple_metrics_and_units(self):
        # 一次识别多个指标，各自带单位与证据
        ocr = ('TC 6.2 mmol/L 2.8-5.2\n'
               'HDL 1.1 mmol/L 0.9-1.8\n'
               '白细胞 WBC 5.8 10^9/L 3.5-9.5')
        ms = parse_metrics(ocr)
        by_code = {m['code']: m for m in ms}
        self.assertEqual(by_code['TC']['unit'], 'mmol/L')
        self.assertEqual(by_code['TC']['status'], 'high')
        self.assertEqual(by_code['HDL']['status'], 'normal')
        self.assertEqual(by_code['WBC']['unit'], '10^9/L')
        self.assertEqual(by_code['WBC']['status'], 'normal')


if __name__ == '__main__':
    unittest.main(verbosity=2)
