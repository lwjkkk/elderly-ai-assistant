"""Parse report cells, never the last number in a flattened OCR line."""
import re
from decimal import Decimal, InvalidOperation

NUMBER = r'[+-]?\d+(?:[.,]\s*\d+)?'
INTERVAL = re.compile(rf'^\s*({NUMBER})\s*(?:--?|[~～〜—–]|至)\s*({NUMBER})\s*$')
LIMIT = re.compile(rf'^\s*(<=|>=|[<>≤≥≦≧])\s*({NUMBER})\s*$')
QUALITATIVE = re.compile(r'^(?:(?:阴性|陽性|阳性|陰性|弱阳性|弱陽性|[+-]{1,4}|\d+\+)(?:\s*[(（][^）)]*[)）])?|[(（]\s*[+-]{1,4}\s*[)）])$')
CODE = re.compile(r'(?<![A-Za-z])(?:25[- ]?OH[- ]?D|HbA1c|eGFR|pH|[A-Za-z]/[A-Za-z]|[A-Za-z][A-Za-z0-9]{1,7}(?:[-/_][A-Za-z0-9]{1,6})?)[#%]?(?![A-Za-z])')
METADATA = re.compile(r'姓名|性别|年龄|编号|病历|床号|科室|诊断|条码|时间|日期|检验者|检验师|检查人员|审核|送检|采样|接收|备注|声明|电话|地址|报告单|医院|标本(?:种类|来源|状态|类型|说明|编号|备注|[:：])|打印|水印|小红书|小结')
UNITLESS = re.compile(r'^(?:pH|SG|AST/ALT|A/G|ABO|PH)$|比重|酸碱度|白蛋白.?球蛋白|谷草.?谷丙', re.I)


def decimal(value):
    try:
        return Decimal(re.sub(r'\s+', '', str(value)).replace(',', '.'))
    except InvalidOperation:
        return None


def reference(text):
    text = text.strip()
    match = INTERVAL.fullmatch(text)
    if match:
        # A leading dash followed by a doubled dash separator can be an OCR
        # artifact or a real minus sign. Preserve the text for review instead
        # of choosing either interpretation (e.g. -11.5--14.5).
        if text.lstrip().startswith('-') and '--' in text[1:]:
            return None
        lo, hi = map(decimal, match.groups())
        if lo is not None and hi is not None and lo <= hi:
            return {'lo': float(lo), 'hi': float(hi), 'lo_inclusive': True,
                    'hi_inclusive': True, 'reference_kind': 'interval'}
    match = LIMIT.fullmatch(text)
    if match:
        operator, value = match.groups()
        value = decimal(value)
        lower = operator in ('>', '>=', '≥', '≧')
        return {'lo': float(value) if lower else None, 'hi': None if lower else float(value),
                'lo_inclusive': operator in ('>=', '≥', '≧'),
                'hi_inclusive': operator in ('<=', '≤', '≦'), 'reference_kind': 'minimum' if lower else 'maximum'}
    return None


def clean_name(text):
    text=text.strip()
    if not re.match(r'^25[- ]?(?:OH|羟)',text,re.I):
        text = re.sub(r'^\d{1,3}\s*(?=[*#（(A-Za-z\u4e00-\u9fff])', '', text)
    text = re.sub(r'[(（]\s*HR\s*[)）]', '', text, flags=re.I)
    return text.strip(' *#·')


def is_name(text):
    text = clean_name(text)
    if not text or METADATA.search(text):
        return False
    # Panel captions are not analytes, even when their parentheses contain
    # valid abbreviations. Keep them out of the preceding table's final row.
    if re.search(r'[一二三四五六七八九十百\d]+项\s*[（(]', text) or re.search(r'[（(][^）)]*(?:[,，、][^）)]*){2,}[）)]', text):
        return False
    if re.search(r'法$|技术$', text):
        return False
    if re.fullmatch(r'[\d\W_]+', text):
        return False
    return bool(re.search(r'[\u4e00-\u9fff]{2,}', text) or CODE.fullmatch(text)
                or re.fullmatch(r'[钾钠氯钙镁磷铁铜锌硒碘]',text))


def metric_name(name, code):
    for token in code.split():
        token = token.lstrip('*#').strip('[]()（）')
        if CODE.fullmatch(token) and token.upper() not in ('HR', 'NULL', 'IFCC'):
            return token
    prefix = CODE.match(clean_name(name))
    if prefix and re.search(r'[\u4e00-\u9fff]',clean_name(name)[prefix.end():]):
        return prefix.group()
    match = next((m for m in CODE.finditer(name) if not name[m.end():].strip(' []()（）')),None)
    if match and match.group().upper() not in ('HR', 'NULL', 'IFCC'):
        return match.group()
    return clean_name(name)


def parse_cells(cells, *, evidence, alignment_ok=True):
    """One metric with independent extraction and comparison states.

    Cells are assigned by table headers before entering this function. Conflicting
    readings are retained for review, never repaired using a physiological range.
    """
    name = clean_name(cells.get('name', ''))
    code = metric_name(name, cells.get('code', ''))
    if not code or not is_name(name or code):
        return None
    result_text = cells.get('result', '').strip()
    range_text = cells.get('reference', '').strip()
    unit_raw = cells.get('unit', '').strip()
    unit = unit_raw if unit_raw not in ('', '-', 'NULL', 'null') else None
    if unit:
        unit = re.sub(r'\s+', '', unit).replace('µ', 'μ')
        unit = unit.lstrip('↑↓←→')
        unit = re.sub(r'^[*×](?=10)', '', unit)
        unit = re.sub(r'^10(?:\^|[eE])?(9|12)/([Ll])$', r'10^\1/\2', unit)
    numeric_text = re.sub(r'\s*[↑↓↗↘]+\s*$', '', result_text)
    value = decimal(numeric_text) if re.fullmatch(NUMBER, numeric_text) else None
    censored = LIMIT.fullmatch(result_text)
    bounds = reference(range_text)
    reasons = []
    review_fields = []
    if not result_text:
        reasons.append('结果单元格缺失，不能使用序号或参考值代替')
        review_fields.append('result')
    elif value is None and not censored and not QUALITATIVE.fullmatch(result_text) and result_text not in ('A型', 'B型', 'AB型', 'O型', '黄色', '淡黄色', '清澈', '清晰'):
        reasons.append('结果不是可唯一确认的数值或定性结果')
        review_fields.append('result')
    if not alignment_ok:
        reasons.append('单元格行归属不明确，请对照原图核对')
        review_fields.append('alignment')
    critical = [b for field in ('name', 'code', 'result', 'reference', 'unit') for b in evidence.get(field, [])]
    if not critical or any(b.get('confidence') is None or b['confidence'] < .90 for b in critical):
        reasons.append('关键字段OCR置信度不足，请核对原图')
        review_fields.append('ocr')
    if value is not None and not bounds:
        reasons.append('报告参考条件缺失或暂不支持，保留结果但不判断高低')
        review_fields.append('reference')
    if value is not None and not unit and not UNITLESS.search(code) and not UNITLESS.search(name):
        reasons.append('计量单位未能确认')
        review_fields.append('unit')
    if unit and not re.fullmatch(r'%|[fF][lL]|[pP][gG]|(?:10\^(?:9|12))/[Ll]|(?:[μu]?mol|mmol|[μu]?g|mg|ng|pg|g|[μu]?U|IU|mIU)/(?:[Ll]|dL|dl|mL|ml)|(?:cell)?/[μu]?[Ll]|/HPF|/100WBC|mmHg|mm/h|L/L|m[lL]/min(?:/1\.73m[²2])?|mOsm/kgH?2?O?',unit):
        reasons.append('单位形式需要人工核对')
        review_fields.append('unit')
    if value is None:
        reasons.append('定性或复合结果已保留，请核对原报告')
    if censored:
        reasons.append('结果为界限值，不能当作精确数值自动比较')
        review_fields.append('result_bound')
    status = 'unparsed'
    def qualitative_key(value):
        value = value.strip('()（） ')
        if value in ('-', '阴性', '陰性', '阴性(-)', '陰性(-)'):
            return 'negative'
        if value in ('+', '阳性', '陽性'):
            return 'positive'
        return value if QUALITATIVE.fullmatch(value) else None
    qualitative_match=bool(value is None and result_text and qualitative_key(result_text)
                           and qualitative_key(result_text)==qualitative_key(range_text))
    if qualitative_match and not review_fields:
        status='normal'
        reasons=[]
    if value is not None and bounds and not reasons:
        lo, hi = bounds['lo'], bounds['hi']
        if lo is not None and (value < decimal(lo) or (value == decimal(lo) and not bounds['lo_inclusive'])):
            status = 'low'
        elif hi is not None and (value > decimal(hi) or (value == decimal(hi) and not bounds['hi_inclusive'])):
            status = 'high'
        else:
            status = 'normal'
    blocks = [b for group in evidence.values() for b in group]
    confidence = min((b['confidence'] for b in critical if b.get('confidence') is not None), default=None)
    qualitative_result=bool(QUALITATIVE.fullmatch(result_text) or result_text in ('A型','B型','AB型','O型','黄色','淡黄色','清澈','清晰'))
    return {'code': code, 'name': name,
            'result': float(value) if value is not None else result_text if qualitative_result or censored else None,
            'result_value': float(value) if value is not None else None,
            'result_kind': 'numeric' if value is not None else 'censored' if censored else 'qualitative' if qualitative_result else 'unknown',
            'result_bound': {'operator':censored[1],'value':float(decimal(censored[2]))} if censored else None,
            'result_text': result_text or None, 'unit': unit, 'unit_raw': unit_raw or None,
            'lo': bounds['lo'] if bounds else None, 'hi': bounds['hi'] if bounds else None,
            **(bounds or {'reference_kind': 'qualitative' if QUALITATIVE.fullmatch(range_text) else 'unknown'}),
            'range_text': range_text or None, 'status': status, 'needs_review': status == 'unparsed',
            'extraction_status': 'complete' if result_text and range_text else 'partial',
            'verification_status': 'verified' if status != 'unparsed' else 'needs_review',
            'comparison_status': ('qualitative_match' if qualitative_match else 'unknown') if value is None else status,
            'review_fields': sorted(set(review_fields)),
            'verification_reason': '；'.join(reasons) or '表头、单元格与数值比较已核对',
            'field_evidence': evidence, 'source_blocks': blocks, 'ocr_confidence': confidence,
            'ocr_text': ' | '.join(cells.get(k, '') for k in ('name','code','result','unit','reference')),
            'parser_version': '3.0.0'}
