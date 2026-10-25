"""Coverage hints only: never fabricate a missing analyte or denominator."""
import re
from statistics import median
from core.report_fields import is_name


def update_coverage(document):
    findings = []
    for table in document['tables']:
        rows = [r for r in document['rows'] if r['table_id'] == table['id']]
        if not rows:
            continue
        anchors = [(r, [b for k in ('name','code') for b in r['fields'].get(k,[])]) for r in rows]
        anchors = [(r,b) for r,b in anchors if b]
        ys = [median(b['cy'] for b in bs) for _,bs in anchors]
        gaps = [b-a for a,b in zip(ys,ys[1:]) if b>a]
        typical = median(gaps) if gaps else None
        if typical and len(gaps)>=3:
            for i, delta in enumerate(gaps):
                if delta > typical*1.65:
                    findings.append({'kind':'row_gap','table_id':table['id'],
                                     'between_rows':[anchors[i][0]['row_index'],anchors[i+1][0]['row_index']],
                                     'y_range':[ys[i],ys[i+1]],'message':'行间距异常，可能存在未定位项目或空行，请对照原图'})
        # Printed serial numbers inside the name column are independent clues.
        serials = []
        for row in rows:
            match = re.match(r'^\s*(\d{1,3})\s*(?=[*#（(A-Za-z\u4e00-\u9fff])', row['cells'].get('name',''))
            if match:
                serials.append((int(match[1]),row['row_index']))
        if len(serials)>=4 and all(0<b[0]-a[0]<=10 for a,b in zip(serials,serials[1:])):
            for a,b in zip(serials,serials[1:]):
                # An intervening unnumbered row may simply have lost its
                # printed ordinal in OCR; its analyte is already present.
                if b[0]-a[0] > b[1]-a[1]:
                    findings.append({'kind':'serial_gap','table_id':table['id'],
                                     'missing_serials':list(range(a[0]+1,b[0])),
                                     'unresolved_row_count':b[0]-a[0]-(b[1]-a[1]),
                                     'between_rows':[a[1],b[1]],'message':'可见项目序号不连续，请核对是否漏项'})
        used = {str(b['polygon']) for r in rows for bs in r['fields'].values() for b in bs}
        columns = sorted(table['columns'].items(),key=lambda x:x[1]['x'])
        for i,(role,column) in enumerate(columns):
            if role not in ('name','code') or not ys:
                continue
            lo = (columns[i-1][1]['x']+column['x'])/2 if i else table['bbox'][0]
            hi = (column['x']+columns[i+1][1]['x'])/2 if i+1<len(columns) else table['bbox'][2]
            for b in document['raw_blocks']:
                if (lo<=b['cx']<hi and min(ys)<=b['cy']<=max(ys)
                        and str(b['polygon']) not in used and is_name(b['text'])):
                    findings.append({'kind':'unmatched_name','table_id':table['id'],
                                     'text':b['text'],'polygon':b['polygon'],
                                     'message':'项目列有未配对文字，请对照原图核对'})
    coverage = document.setdefault('coverage', {})
    coverage.update(scope='detected_tables_only',complete_report_verified=False,
                    findings=findings[:30],findings_truncated=len(findings)>30,
                    detected_table_count=len(document['tables']),
                    detected_metric_count=len(document.get('metrics',[])))
    if findings:
        document['warnings'].append(f'发现{len(findings)}处疑似漏项或未配对区域，请查看原图；提示不表示已确认缺少对应项目')
