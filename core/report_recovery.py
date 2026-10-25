"""Bounded, image-backed field recovery. No physiological or drug-name guesses."""
import re
from statistics import median

from core.report_fields import NUMBER, reference

UNIT = re.compile(r'%|[fF][lL]|[pP][gG]|(?:10[\^eE]?(?:9|12))/[Ll]|(?:[μµu]?mol|mmol|[μu]?g|g|mg|ng|pg|[μu]?U|IU|mIU)/(?:[Ll]|d[Ll]|m[Ll])|(?:cell)?/[μu]?[Ll]|/HPF|/100WBC|mmHg|mm/h|L/L|m[lL]/min(?:/1\.73m[²2])?|mOsm/kgH?2?O?')


def valid_reading(field, value):
    if field == 'result':
        return bool(re.fullmatch(NUMBER, re.sub(r'\s*[↑↓↗↘]+\s*$', '', value)))
    if field == 'reference':
        return bool(reference(value))
    return bool(UNIT.fullmatch(canonical(field,value)))


def canonical(field, value):
    value = re.sub(r'\s+', '', value).replace('µ', 'μ')
    if field == 'unit':
        value = re.sub(r'^[*×](?=10)', '', value)
        return re.sub(r'^10(?:\^|[eE])?(9|12)/([Ll])$', r'10^\1/\2', value)
    if field == 'result':
        from core.report_fields import decimal
        plain = re.sub(r'[↑↓↗↘]+$', '', value)
        if re.fullmatch(NUMBER,plain):
            return str(decimal(plain).normalize())
    return value


def locate_crop(document, row, field):
    """Interpolate neighbouring cells within this table, including local tilt."""
    current = row['fields'].get(field, [])
    if current:
        points = [p for b in current for p in b.get('polygon', [])]
        if not points:
            return None
        xs, ys = zip(*points)
        pad = max(3, int(median(b['h'] for b in current) * .2))
        return [int(min(xs))-pad, int(min(ys))-pad, int(max(xs))+pad, int(max(ys))+pad]
    neighbours = [(other['row_index'], other['fields'].get(field, []))
                  for other in document['rows'] if other['table_id'] == row['table_id']
                  and other['fields'].get(field)]
    before = [p for p in neighbours if p[0] < row['row_index']]
    after = [p for p in neighbours if p[0] > row['row_index']]
    if not before or not after:
        return None  # Do not extrapolate first/last rows into a header/footer.
    a, ba = max(before, key=lambda p:p[0])
    b, bb = min(after, key=lambda p:p[0])
    fraction = (row['row_index']-a)/(b-a)
    ya, yb = median(x['cy'] for x in ba), median(x['cy'] for x in bb)
    step = (yb-ya)/(b-a)
    cy = ya + fraction*(yb-ya)
    cx = median(x['cx'] for x in ba)*(1-fraction) + median(x['cx'] for x in bb)*fraction
    peers = [box for _, group in neighbours for box in group]
    half_width = max(16, median(max(p[0] for p in box['polygon'])-min(p[0] for p in box['polygon']) for box in peers)*.65)
    return [int(cx-half_width), int(cy-step*.43), int(cx+half_width), int(cy+step*.43)]


def merged_result_crop(row, crop):
    """Narrow a geometrically overlapping name box; never split B12/HbA1c text."""
    name = row['cells'].get('name', '')
    match = re.search(r'(?P<number>\d+(?:[.,]\d+)?)\s*$', name)
    if not match:
        return None
    prefix = name[:match.start()]
    # Integer suffixes attached to an ASCII code are part of its name until
    # independently confirmed by a human; decimal suffixes can be candidates.
    if '.' not in match.group() and ',' not in match.group() and (not prefix or not re.search(r'[\u4e00-\u9fff]$', prefix)):
        return None
    blocks = row['fields'].get('name', [])
    if not blocks:
        return None
    right = max(p[0] for b in blocks for p in b['polygon'])
    if right < (crop[0]+crop[2])/2 - (crop[2]-crop[0])*.4:
        return None
    # A narrower recognition window is a new image observation, not a regex
    # extraction. The original name and evidence are retained for review.
    width = crop[2]-crop[0]
    return [int(crop[0]+width*.20), crop[1], crop[2], crop[3]]


def choose_reading(field, observations, original, original_valid, require_agreement=False):
    """Distinct valid alternatives veto acceptance, including low-confidence ones."""
    alternatives = {canonical(field, x['text']) for x in observations if valid_reading(field, x['text'])}
    confident = [x for x in observations if valid_reading(field, x['text']) and x['confident']]
    if len(alternatives) != 1 or not confident:
        return None
    if require_agreement and len(confident) < 2:
        return None
    chosen = confident[0]
    if original_valid and canonical(field, original) != canonical(field, chosen['text']):
        return None
    return chosen
