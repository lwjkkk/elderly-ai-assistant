# -*- coding: utf-8 -*-
"""OCR 端到端测试：真实 paddle 模型对体检单样张执行 图片→base64→recognize_image 全链路。

运行：D:\\python\\python.exe -X utf8 backend_validation/test_ocr_e2e.py
"""
import base64
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import ocr

SAMPLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sample_report.png')
KEY_FIELDS = ['血糖', '谷丙转氨酶', '血压', '总胆固醇', '7.2', '120/80', 'mmol/L', 'mmHg']


def main():
    if not os.path.exists(SAMPLE):
        print('FAIL: 缺少样张', SAMPLE)
        sys.exit(2)
    with open(SAMPLE, 'rb') as f:
        b64 = base64.b64encode(f.read()).decode()
    t0 = time.time()
    try:
        text = ocr.recognize_image(b64)
    except Exception as e:
        print('FAIL: recognize_image 抛异常: %r (%s)' % (e, type(e).__name__))
        sys.exit(1)
    print('OCR 耗时 %.1fs' % (time.time() - t0))
    print('---- 识别结果 ----')
    print(text)
    print('------------------')
    missed = [k for k in KEY_FIELDS if k not in text]
    if missed:
        print('FAIL: 以下关键字段未被识别:', missed)
        sys.exit(1)
    print('PASS: 关键字段全部识别命中 (%d/%d)' % (len(KEY_FIELDS) - len(missed), len(KEY_FIELDS)))


if __name__ == '__main__':
    main()
