"""Resolve explicit OCR spans without discarding their original evidence."""
import re

from core.report_fields import NUMBER, clean_name, metric_name, reference
from core.report_recovery import canonical, valid_reading


def split_reference_unit(row, cells, fields):
    combined = cells.get('reference', '')
    # Whitespace and the following % can identify the very same split twice.
    splits = {(combined[:n].strip(), combined[n:].strip())
              for n in range(1, len(combined))
              if (combined[n].isspace() or combined[n] == '%')
              and reference(combined[:n].strip())
              and valid_reading('unit', combined[n:].strip())}
    if len(splits) != 1:
        return
    ref, unit = splits.pop()
    existing = cells.get('unit', '')
    if not existing:
        cells['reference'], cells['unit'] = ref, unit
        fields['unit'] = list(fields['reference'])
        row['joined_field_split'] = {'original': combined, 'reference': ref, 'unit': unit}
    elif canonical('unit', existing) != canonical('unit', unit):
        row['alignment_ok'] = False
        row['joined_field_conflict'] = {'original': combined, 'unit': existing, 'candidate_unit': unit}
    else:
        cells['reference'] = ref
        row['joined_field_split'] = {'original': combined, 'reference': ref, 'unit': unit}


def split_code_result(row, cells, fields):
    """A printed code prefix ending in '-' plus its adjacent '(suffix)' box.

    Numeric parentheses, flags and a single inseparable OCR box are deliberately
    not interpreted as a code suffix. Their original readings remain available.
    """
    groups = sorted(fields.get('result', []), key=lambda b: b['cx'])
    if len(groups) < 2:
        return
    match = re.fullmatch(r'[(（]\s*([A-Za-z]{1,4})\s*[)）]', groups[0]['text'].strip())
    if not match:
        return
    base_match = re.match(r'^([A-Za-z][A-Za-z0-9]{1,7})[-_]', clean_name(cells.get('name', '')))
    if not base_match:
        base_match = re.fullmatch(r'([A-Za-z][A-Za-z0-9]{1,7})[-_]',cells.get('code','').strip())
    if not base_match:
        return
    remainder = ' '.join(b['text'] for b in groups[1:]).strip()
    if not re.fullmatch(NUMBER, remainder):
        return
    prefix, numeric = groups[0], groups[1:]
    names = fields.get('name', [])
    if not names or max(p[0] for b in names for p in b['polygon']) + max(prefix['h'], 1)*2 < min(p[0] for p in prefix['polygon']):
        return
    if max(p[0] for p in prefix['polygon']) > min(p[0] for b in numeric for p in b['polygon']):
        return
    code = base_match[1] + '-' + match[1]
    explicit_code = cells.get('code', '')
    if explicit_code and explicit_code.strip().rstrip('-_').upper()!=base_match[1].upper() and metric_name('', explicit_code).upper() not in (base_match[1].upper(), code.upper()):
        row['alignment_ok'] = False
        return
    row['code_result_split'] = {'original': cells['result'], 'original_name': cells['name'],
                                'code': code, 'result': remainder, 'source_blocks': groups}
    cells['code'], cells['result'] = code, remainder
    cells['name'] += ' ' + prefix['text']
    fields['code'] = list(fields.get('code', []) or names) + [prefix]
    fields['result'] = numeric
