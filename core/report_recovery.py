"""Bounded, image-backed field recovery. No physiological or drug-name guesses."""
import re
from statistics import median

from core.report_fields import NUMBER, reference, QUALITATIVE, LIMIT, qualitative_key, is_name

UNIT = re.compile(r'%|[fF][lL]|[pP][gG]|(?:10[\^eE]?(?:9|12))/[Ll]|(?:[μµu]?mol|mmol|[μu]?g|g|mg|ng|pg|[μu]?U|IU|mIU)/(?:[Ll]|d[Ll]|m[Ll])|(?:cell)?/[μu]?[Ll]|/HPF|/100WBC|mmHg|mm/h|L/L|m[lL]/min(?:/1\.73m[²2])?|mOsm/kgH?2?O?')


def valid_reading(field, value):
    if field == 'result':
        return bool(re.fullmatch(NUMBER, re.sub(r'\s*[↑↓↗↘]+\s*$', '', value))
                    or LIMIT.fullmatch(value)
                    or (QUALITATIVE.fullmatch(value) and qualitative_key(value) is not None))
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
        if QUALITATIVE.fullmatch(value) and qualitative_key(value) is not None:
            return 'qualitative:'+qualitative_key(value)
    return value


def locate_crop(document, row, field):
    """Interpolate neighbouring cells within this table, including local tilt."""
    current = row.get('field_crop_sources',{}).get(field,row['fields'].get(field, []))
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
        # Edge recovery is allowed only for an actual, clear name anchor and a
        # nearby populated column. Never manufacture a new row or cross tables.
        anchors = row['fields'].get('name',[]) or row['fields'].get('code',[])
        if (len(neighbours)<4 or not anchors
                or not is_name(' '.join(b['text'] for b in anchors))
                or any(b.get('confidence') is None or b['confidence']<.90 for b in anchors)
                or min(abs(i-row['row_index']) for i,_ in neighbours)>3):
            return None
        peer_rows = [r for r in document['rows'] if r['table_id']==row['table_id']]
        paired = [(r,r['fields'].get(field,[]),r['fields'].get('name',[]) or r['fields'].get('code',[]))
                  for r in peer_rows if r['fields'].get(field)
                  and (r['fields'].get('name') or r['fields'].get('code'))]
        if len(paired)<4:
            return None
        paired = sorted(paired,key=lambda x:abs(x[0]['row_index']-row['row_index']))[:6]
        offset = median(median(b['cy'] for b in fields)-median(b['cy'] for b in names)
                        for _,fields,names in paired)
        cy = median(b['cy'] for b in anchors)+offset
        positions = sorted((r['row_index'],median(b['cy'] for b in (r['fields'].get('name',[]) or r['fields'].get('code',[]))))
                           for r in peer_rows if r['fields'].get('name') or r['fields'].get('code'))
        steps = [(yb-ya)/(ib-ia) for (ia,ya),(ib,yb) in zip(positions,positions[1:]) if ib>ia and yb>ya]
        if not steps:
            return None
        step = median(steps)
        peers = [b for _,fields,_ in paired for b in fields]
        cx = median(b['cx'] for b in peers)
        half_width = max(16,median(max(p[0] for p in b['polygon'])-min(p[0] for p in b['polygon']) for b in peers)*.65)
        half_height = min(step*.48,max(step*.43,median(b['h'] for b in anchors)*.55))
        table = next((t for t in document.get('tables',[]) if t['id']==row['table_id']),None)
        if not table or cy-half_height<table['bbox'][1] or cy+half_height>table['bbox'][3]:
            return None
        row.setdefault('inferred_crop',{})[field] = 'bounded_edge_from_existing_name_anchor'
        return [int(cx-half_width),int(cy-half_height),int(cx+half_width),int(cy+half_height)]
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
