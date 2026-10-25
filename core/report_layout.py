"""Header-guided report tables. Coordinates, missing cells and ambiguity survive parsing."""
import re
from statistics import median
from core.report_fields import is_name, reference, QUALITATIVE, NUMBER, METADATA

LABELS = {
    'result': re.compile(r'^(?:检测|检验|测定|检查)?结果$'),
    'reference': re.compile(r'^(?:参考(?:范围|区间|值|区)?|正常(?:范围|值))$'),
    'unit': re.compile(r'^(?:结果|计量)?单位$'),
    'code': re.compile(r'^(?:序号)?(?:英文(?:缩写|名称|名)?|简称|代号|代码|项目(?:简称|编码|代码))$'),
    'name': re.compile(r'^(?:序号)?(?:检验|检查|检测|测定)?项目(?:名称|名)?(?:[（(]项目?简称[）)])?$|^中文(?:名|名称)$'),
    'method': re.compile(r'^(?:检测|检验|测定)?方法$|^仪器$'),
    'flag': re.compile(r'^(?:结果)?提示$|^标志$|^状态$'),
    'serial': re.compile(r'^序号$|^NO$', re.I),
}


def text(blocks):
    return ' '.join(b['text'] for b in sorted(blocks, key=lambda b: b['cx'])).strip()


def headers(blocks):
    found = []
    for b in blocks:
        value = re.sub(r'\s+', '', b['text'])
        combined = re.fullmatch(r'(项目编码|项目代码|代号|代码)(项目)', value)
        if combined:
            xs = [p[0] for p in b['polygon']]
            left, right = min(xs), max(xs)
            split = len(combined[1])/len(value)
            for role, fraction in [('code',split/2),('name',(1+split)/2)]:
                found.append({**b,'role':role,'cx':left+fraction*(right-left),'_original':b})
            continue
        if value in ('单位参考值', '单位参考区间', '单位参考范围'):
            xs = [p[0] for p in b['polygon']]
            left, right = min(xs), max(xs)
            # Header words may share one OCR box; keep the original as evidence.
            for role, fraction in [('unit', 1 / len(value)), ('reference', (2 + (len(value)-2)/2)/len(value))]:
                found.append({**b, 'role': role, 'cx': left + fraction * (right-left), '_original': b})
        else:
            for role, pattern in LABELS.items():
                if pattern.fullmatch(value):
                    found.append({**b, 'role': role, '_original': b})
                    break
        # Widely spaced 项 目 are sometimes detected as individual characters.
        if value == '项':
            neighbours = [o for o in blocks if o['text'].strip() == '目' and
                          0 < o['cx']-b['cx'] < b['h']*6 and abs(o['cy']-b['cy']) < b['h']]
            if neighbours:
                o = min(neighbours, key=lambda o: o['cx'])
                found.append({**b, 'role': 'name', 'cx': (b['cx']+o['cx'])/2, '_original': b})
    return found


def group_column(blocks):
    groups = []
    for b in sorted(blocks, key=lambda b: b['cy']):
        if groups and abs(b['cy']-median(x['cy'] for x in groups[-1])) < .45*median(x['h'] for x in groups[-1]):
            groups[-1].append(b)
        else:
            groups.append([b])
    return groups


def gap(groups, default):
    ys = [median(b['cy'] for b in row) for row in groups]
    diffs = [b-a for a,b in zip(ys,ys[1:]) if b-a > default*.20]
    if not diffs:
        return default
    estimate = median(diffs)
    small = [d for d in diffs if d < estimate*1.6]
    estimate = median(small or diffs)
    return estimate if default*.30 < estimate < default*1.6 else default


def reconstruct(blocks, width, height):
    """Return rows with field boxes; unknown geometry never silently uses legacy guesses."""
    hs = headers(blocks)
    seeds = sorted([h for h in hs if h['role'] == 'result'], key=lambda h:(h['cy'],h['cx']))
    consumed_headers = {id(h['_original']) for h in hs}
    rows, tables = [], []
    def boundary(a, b):
        near=[h for h in hs if a['cx']<h['cx']<b['cx'] and
              abs(h['cy']-a['cy'])<max(3*a['h'],abs(h['cx']-a['cx'])*.15)]
        next_names=[h['cx'] for h in near if h['role'] in ('name','code')]
        if not next_names:
            return (a['cx']+b['cx'])/2
        name=min(next_names)
        previous=[h['cx'] for h in near if h['role'] in ('unit','reference','method','flag') and h['cx']<name]
        return (max(previous)+name)/2 if previous else (a['cx']+name)/2
    for seed in seeds:
        peers = [h for h in seeds if (h is seed or abs(h['cx']-seed['cx'])>max(80,seed['h']*2))
                 and abs(h['cy']-seed['cy']) < max(3*seed['h'],abs(h['cx']-seed['cx'])*.15)]
        left = max([h['cx'] for h in peers if h['cx'] < seed['cx']],default=None)
        right = min([h['cx'] for h in peers if h['cx'] > seed['cx']],default=None)
        xmin = boundary(next(h for h in peers if h['cx']==left),seed) if left is not None else 0
        xmax = boundary(seed,next(h for h in peers if h['cx']==right)) if right is not None else width
        candidates = [h for h in hs if xmin <= h['cx'] < xmax and
                      abs(h['cy']-seed['cy']) < max(3*seed['h'],abs(h['cx']-seed['cx'])*.15)]
        names = [h for h in candidates if h['role'] in ('name','code') and h['cx'] < seed['cx']]
        references = [h for h in candidates if h['role']=='reference' and h['cx'] > seed['cx']]
        if not names or not references:
            continue
        selected = {}
        for h in candidates:
            role=h['role']
            if role not in selected or abs(h['cy']-seed['cy']) < abs(selected[role]['cy']-seed['cy']):
                selected[role]=h
        selected['result']=seed
        columns = sorted(selected.values(),key=lambda h:h['cx'])
        later = [h for h in seeds if h not in peers and xmin <= h['cx'] < xmax and h['cy'] > seed['cy']]
        ymax = min((h['cy']-h['h'] for h in later),default=height)
        if later:
            section_metadata = [b['cy']-b['h']/2 for b in blocks
                                if xmin<=b['cx']<xmax and seed['cy']+seed['h']*3<b['cy']<ymax
                                and re.search(r'(?:检查|检验|报告)日期|检查人员',b['text'])]
            ymax = min([ymax]+section_metadata)
        col_groups = {}
        serial_names = []
        for index, column in enumerate(columns):
            lo = (columns[index-1]['cx']+column['cx'])/2 if index else xmin
            hi = (column['cx']+columns[index+1]['cx'])/2 if index+1<len(columns) else xmax
            found = [b for b in blocks if id(b) not in consumed_headers and b.get('polygon') and
                     lo <= b['cx'] < hi and column['cy']+column['h']*.3 < b['cy'] < ymax]
            if column['role'] in ('name','code'):
                found = [b for b in found if is_name(b['text'])]
            if column['role']=='serial':
                serial_names=[b for b in found if is_name(b['text'])]
            col_groups[column['role']]=group_column(found)
        if serial_names:
            existing=[b for row in col_groups.get('name',[]) for b in row]
            col_groups['name']=group_column(existing+serial_names)
        primary = 'name' if len(col_groups.get('name',[]))>=max(1,len(col_groups.get('code',[]))*.5) else 'code'
        anchors = col_groups.get(primary,[])
        if not anchors:
            continue
        anchor_header=selected[primary]
        anchor_gap=gap(anchors,median(b['h'] for row in anchors for b in row)*1.5)
        # Exclude footer text and secondary panels without a matching header.
        anchors=[a for a in anchors if not METADATA.search(text(a))]
        for n in range(1,len(anchors)):
            if median(b['cy'] for b in anchors[n])-median(b['cy'] for b in anchors[n-1])>anchor_gap*3.5:
                anchors=anchors[:n]
                break
        table_id=len(tables)
        tables.append({'id':table_id,'bbox':[xmin,min(h['cy'] for h in columns),xmax,ymax],
                       'columns':{h['role']:{'x':h['cx'],'y':h['cy']} for h in columns}})
        table_rows=[{'fields':{primary:a},'alignment_ok':True,'table_id':table_id,
                     'row_index':i,'alignment':{primary:'anchor'}} for i,a in enumerate(anchors)]
        for role,groups in col_groups.items():
            if role==primary or role in ('method','flag','serial'):
                continue
            header=selected[role]
            # Numeric flags usually sit to the right of an aligned result column.
            if role=='result':
                numeric=[b for g in groups for b in g if re.fullmatch(NUMBER,b['text'].strip())]
                if len(numeric)>=4:
                    slopes=[(b['cx']-a['cx'])/(b['cy']-a['cy']) for n,a in enumerate(numeric) for b in numeric[n+1:]
                            if abs(b['cy']-a['cy'])>anchor_gap*2 and abs((b['cx']-a['cx'])/(b['cy']-a['cy']))<.4]
                    slope=median(slopes or [0])
                    center=median(b['cx']-slope*b['cy'] for b in numeric)
                    typical_width=median(max(p[0] for p in b['polygon'])-min(p[0] for p in b['polygon']) for b in numeric)
                    tolerance=max(12,typical_width*.8)
                    groups=[[b for b in g if not re.fullmatch(NUMBER,b['text'].strip()) or abs(b['cx']-slope*b['cy']-center)<=tolerance] for g in groups]
                    groups=[g for g in groups if g]
            if role=='reference':
                valid=[b for g in groups for b in g if reference(b['text']) or QUALITATIVE.fullmatch(b['text'].strip())]
                if len(valid)>=3:
                    slopes=[(b['cx']-a['cx'])/(b['cy']-a['cy']) for n,a in enumerate(valid) for b in valid[n+1:]
                            if abs(b['cy']-a['cy'])>anchor_gap*2 and abs((b['cx']-a['cx'])/(b['cy']-a['cy']))<.4]
                    slope=median(slopes or [0]);center=median(b['cx']-slope*b['cy'] for b in valid)
                    tolerance=max(16,median(max(p[0] for p in b['polygon'])-min(p[0] for p in b['polygon']) for b in valid)*.8)
                    groups=[[b for b in g if abs(b['cx']-slope*b['cy']-center)<=tolerance] for g in groups]
                    groups=[g for g in groups if g]
            def usable(g):
                value=text(g).strip()
                if role=='reference':return bool(value) and not METADATA.search(value)
                if role=='result':return bool(re.search(r'\d',value) or QUALITATIVE.fullmatch(value) or re.search(r'型|清澈|黄色|清晰',value))
                return True
            data=[g for g in groups if usable(g) and median(b['cy'] for b in g)<=median(b['cy'] for b in anchors[-1])+anchor_gap]
            column_gap=gap(data,anchor_gap)
            dense=role in ('result','reference','code','unit') and len(data)>=max(4,len(anchors)*.70)
            progress=[]
            if dense and data:
                top_column=gap(data[:6],column_gap)
                top_anchor=gap(anchors[:6],anchor_gap)
                start=(median(b['cy'] for b in data[0])-header['cy'])/top_column - (median(b['cy'] for b in anchors[0])-anchor_header['cy'])/top_anchor
                cursor=round(start)
                for n,g in enumerate(data):
                    if n:
                        delta=median(b['cy'] for b in g)-median(b['cy'] for b in data[n-1])
                        local_diffs=[median(b['cy'] for b in data[j])-median(b['cy'] for b in data[j-1]) for j in range(max(1,n-3),min(len(data),n+4))]
                        normal=median([d for d in local_diffs if d < column_gap*1.6] or [column_gap])
                        cursor+=max(1,round(delta/normal))
                    progress.append(cursor)
                dense=(abs(start-round(start)) < .40 and len(set(progress))==len(progress)
                       and progress[0]>=0 and progress[-1]<len(anchors)
                       and len(anchors)-1-progress[-1]<=1)
            tables[-1].setdefault('alignment_diagnostics',{})[role]={'dense':dense,'count':len(data),
                'start':start if progress else None,'progress':progress,'anchor_count':len(anchors),
                'anchor_gap':anchor_gap,'column_gap':column_gap,'anchor_y':median(b['cy'] for b in anchors[0]),
                'first_y':median(b['cy'] for b in data[0]) if data else None,
                'header_y':header['cy'],'name_header_y':anchor_header['cy'],
                'top_gaps':[top_column,top_anchor] if progress else None}
            for n,g in enumerate(data):
                t=(median(b['cy'] for b in g)-header['cy'])/column_gap
                distances=sorted((abs(t-(median(b['cy'] for b in a)-anchor_header['cy'])/anchor_gap),i) for i,a in enumerate(anchors))
                distance,index=distances[0]
                clear=distance<.45 and (len(distances)<2 or distances[1][0]-distance>.12)
                if dense:
                    index=progress[n]
                    clear=True
                if not clear:
                    continue
                target=table_rows[index]
                if role in target['fields']:
                    target['alignment_ok']=False
                    target['fields'][role]+=g
                else:
                    target['fields'][role]=g
                target['alignment'][role]='ordered_grid' if dense else 'header_relative_position'
        rows.extend(table_rows)
    return rows,tables
