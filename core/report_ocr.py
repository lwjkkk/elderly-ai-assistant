"""Report-only OCR: spatial evidence, bounded local retries, conservative parsing."""
import os
import re
from copy import deepcopy
from statistics import median

from core.ocr import (_decode_image, recognize_blocks, _reconstruct_table_rows,
                      OcrNoTextError)
from core.report_parse import parse_metrics

VERSION = "report-ocr-2.5"
LOW_CONFIDENCE = 0.90  # Operational review threshold, not calibrated accuracy.
MAX_RETRIES = 6
MAX_RECOGNITION_CALLS = 12


def _spatial_rows(blocks, width):
    """Remove local baseline tilt for row matching; evidence stays in original pixels."""
    slopes = []
    for b in blocks:
        p = b.get("polygon")
        if p and len(p) >= 4 and p[1][0] - p[0][0] > 50:
            slope = (p[1][1] - p[0][1]) / (p[1][0] - p[0][0])
            if abs(slope) < .15:
                slopes.append((b["cy"], slope))
    adjusted = []
    for index, b in enumerate(blocks):
        local = [s for y, s in slopes if abs(y - b["cy"]) < 150]
        slope = median(local) if local else 0
        adjusted.append({**b, "cy": b["cy"] - slope * b["cx"], "_index": index})
    return [[blocks[b["_index"]] for b in row]
            for row in _reconstruct_table_rows(adjusted, width)]


def _warnings(arr):
    import cv2
    gray = cv2.cvtColor(arr, cv2.COLOR_BGR2GRAY)
    warnings = []
    if min(arr.shape[:2]) < 600:
        warnings.append("图片较小，小字可能不清晰；建议上传原图")
    if cv2.Laplacian(gray, cv2.CV_64F).var() < 35:
        warnings.append("图片可能模糊，请核对小数点和数字")
    if float(gray.mean()) < 55:
        warnings.append("图片偏暗，建议在均匀光线下重新拍摄")
    return warnings


def recognize_report(image_base64):
    arr = _decode_image(image_base64)
    if min(arr.shape[:2]) < 32:
        raise ValueError("图片尺寸过小，请上传完整、清晰的体检报告原图")
    if arr.shape[0] * arr.shape[1] > 40_000_000:
        raise ValueError("图片像素过大，请上传不超过4000万像素的清晰报告图片")
    blocks = recognize_blocks(arr)
    document = document_from_blocks(blocks, int(arr.shape[1]), int(arr.shape[0]))
    from core.report_preprocess import select_view,restore_coordinates
    working,document,forward,preprocessing = select_view(arr,document,recognize_blocks,document_from_blocks)
    if preprocessing['orientation_status']=='incorrect' or not document['tables']:
        document['recognition_call_count'] = 0
        document['retry_budget'] = {'max_fields':MAX_RETRIES,'max_calls':MAX_RECOGNITION_CALLS,'exhausted':False}
        preprocessing['local_refinement_skipped'] = True
    else:
        refine_document(document, working)
    document = restore_coordinates(document,forward,arr.shape)
    document['preprocessing'] = preprocessing
    document['warnings'] = _warnings(arr) + document['warnings']
    document['models'] = {'det': os.getenv('OCR_DET_MODEL', 'PP-OCRv6_medium_det'),
                          'rec': os.getenv('OCR_REC_MODEL', 'PP-OCRv6_medium_rec')}
    from core.report_quality import assess_report,ReportRetakeRequired
    assess_report(document)
    if document['retake_required']:
        raise ReportRetakeRequired(document)
    return "\n".join(row['text'] for row in document['rows']), document


def document_from_blocks(blocks, width, height):
    """Also used to replay saved real OCR boxes; never substitutes recognition output."""
    from core.report_layout import reconstruct, text
    rows, tables = reconstruct(blocks, width, height)
    prepared = []
    for index, row in enumerate(rows):
        fields = row['fields']
        # Flags are not part of the numeric result or its confidence.
        for field in ('result','unit'):
            fields[field] = [b for b in fields.get(field, [])
                             if not re.fullmatch(r'[↑↓←→*ⅠIiTt]+', b['text'].strip())]
        cells = {role: text(value) for role, value in fields.items()}
        from core.report_cells import split_reference_unit,split_code_result
        split_reference_unit(row,cells,fields)
        split_code_result(row,cells,fields)
        prepared.append({**row, 'cells': cells, 'text': ' | '.join(cells.get(k,'') for k in ('name','code','result','unit','reference')),
                         'blocks': [b for value in fields.values() for b in value], 'source_line': index})
    document = {'version': VERSION, 'width': width, 'height': height,
                'coordinate_space': 'original_image_pixels', 'raw_blocks': blocks,
                'tables': tables, 'rows': prepared, 'retry_count': 0,
                'coverage': {'scope':'detected_tables_only','complete_report_verified':False},
                'warnings': [] if tables else ['未找到可靠的报告表头，未自动判断指标；请上传包含表头的清晰原图']}
    if tables:
        document['warnings'].append('结果仅覆盖已定位表格；倒置、折叠、截断或缺少表头的区域可能未完整识别，请对照原图核对')
    document['metrics'] = parse_report_document(document)
    return document


def refine_document(document, arr):
    """Image-backed recovery with independent views and a shared call budget."""
    import cv2
    from core.report_fields import reference, QUALITATIVE
    from core.report_layout import text
    from core.report_recovery import (locate_crop, merged_result_crop, valid_reading,
                                      choose_reading, canonical, merged_name_crop,
                                      name_boundary_confirmed)
    from core.report_coverage import update_coverage
    tasks = []
    metrics_by_row = {m['source_line']:m for m in document['metrics']}
    for index,row in enumerate(document['rows']):
        metric = metrics_by_row.get(index)
        if not metric:
            continue
        for field in ('result','unit','reference','name','code'):
            current = row['fields'].get(field,[])
            low = any(b.get('confidence') is None or b['confidence']<LOW_CONFIDENCE for b in current)
            if field=='code' and row.get('code_result_split'):
                continue
            if field=='name' and canonical('name',text(current))!=canonical('name',row['cells'].get('name','')):
                continue  # A derived name needs all of its original spans.
            missing_result = field=='result' and not row['cells'].get('result')
            invalid_result = (field=='result' and bool(current)
                              and 'result' in metric['review_fields'])
            invalid_unit = field=='unit' and 'unit' in metric['review_fields'] and bool(current)
            ref_text = row['cells'].get('reference','')
            if field=='reference' and metric.get('result_kind')=='qualitative' and not QUALITATIVE.fullmatch(ref_text):
                continue  # Explanatory text is not an unreadable numeric range.
            missing_ref = field=='reference' and not ref_text and metric.get('result_kind')=='numeric'
            invalid_ref = field=='reference' and bool(current) and not reference(ref_text) and not QUALITATIVE.fullmatch(ref_text)
            if missing_result or invalid_result or invalid_unit or low or missing_ref or invalid_ref:
                priority = 0 if missing_result or invalid_result else 1 if invalid_unit else 2 if low and field in ('name','code') else 3 if missing_ref else 4 if low else 5
                tasks.append((priority,index,field))
    document['recognition_call_count'] = 0
    for _,index,field in sorted(tasks)[:MAX_RETRIES]:
        if document['recognition_call_count']>=MAX_RECOGNITION_CALLS:
            break
        row = document['rows'][index]
        crop = locate_crop(document,row,field)
        if not crop:
            continue
        original = row['cells'].get(field,'')
        alignment_before = row['alignment_ok']
        entry = {'crop':crop,'original':original,'candidate':'','blocks':[],
                 'accepted':False,'observations':[]}
        row.setdefault('retry_fields',{})[field] = entry

        def observe(bounds, variant, observations=None):
            x0,y0,x1,y1 = bounds
            x0,y0,x1,y1 = max(0,x0),max(0,y0),min(arr.shape[1],x1),min(arr.shape[0],y1)
            if x1<=x0 or y1<=y0 or document['recognition_call_count']>=MAX_RECOGNITION_CALLS:
                return
            document['recognition_call_count'] += 1
            scale = 1 if variant=='original' else 2
            image = arr[y0:y1,x0:x1]
            if scale!=1:
                image = cv2.resize(image,None,fx=scale,fy=scale,interpolation=cv2.INTER_CUBIC)
            if variant=='contrast':
                lab = cv2.cvtColor(image,cv2.COLOR_BGR2LAB)
                lab[:,:,0] = cv2.createCLAHE(clipLimit=2.0,tileGridSize=(4,4)).apply(lab[:,:,0])
                image = cv2.cvtColor(lab,cv2.COLOR_LAB2BGR)
            try:
                predicted = recognize_blocks(image)
                mapped = []
                for block in predicted:
                    if re.fullmatch(r'[↑↓←→*ⅠIiTt]+',block['text'].strip()):
                        continue
                    polygon = [[x0+x/scale,y0+y/scale] for x,y in block['polygon']]
                    mapped.append({**block,'polygon':polygon,'cx':x0+block['cx']/scale,
                                   'cy':y0+block['cy']/scale,'h':block['h']/scale})
                value = text(mapped)
                confident = bool(mapped) and all(b.get('confidence') is not None and b['confidence']>=LOW_CONFIDENCE for b in mapped)
                target = entry['observations'] if observations is None else observations
                target.append({'variant':variant,'crop':[x0,y0,x1,y1],
                               'text':value,'blocks':mapped,'confident':confident})
            except Exception:
                entry.setdefault('errors',[]).append(variant)
                row.setdefault('retry_errors',[]).append(field)

        if field=='unit':
            for variant in ('original','enlarged','contrast'):
                observe(crop,variant)
        elif field in ('name','code'):
            observe(crop,'enlarged')
            observe(crop,'contrast')
        else:
            observe(crop,'enlarged')
        edge_result = field=='result' and field in row.get('inferred_crop',{})
        qualitative_result = field=='result' and any(QUALITATIVE.fullmatch(o['text']) for o in entry['observations'])
        if field=='result' and (edge_result or qualitative_result):
            observe(crop,'contrast')
            readings = [o for o in entry['observations'] if valid_reading(field,o['text']) and o['confident']]
            if len(readings)<2:
                observe(crop,'original')
        merged_crop = merged_result_crop(row,crop) if field=='result' and not original else None
        if merged_crop and any(valid_reading(field,o['text']) for o in entry['observations']):
            observe(crop,'contrast')
        if merged_crop and not any(valid_reading(field,o['text']) for o in entry['observations']):
            observe(merged_crop,'enlarged')
            observe(merged_crop,'contrast')
            entry['merged_name_candidate'] = True
        old_valid = valid_reading(field,original)
        chosen = choose_reading(field,entry['observations'],original,old_valid,
                                require_agreement=field in ('unit','name','code') or edge_result or qualitative_result or bool(merged_crop))
        entry['candidate'] = chosen['text'] if chosen else (entry['observations'][0]['text'] if entry['observations'] else '')
        entry['blocks'] = chosen['blocks'] if chosen else []
        alternatives = {canonical(field,o['text']) for o in entry['observations'] if valid_reading(field,o['text'])}
        if chosen:
            row['fields'][field] = chosen['blocks']
            row['cells'][field] = chosen['text']
            entry['accepted'] = True
            if merged_crop:
                boundary = merged_name_crop(row,chosen['blocks'],chosen['text'])
                name_observations = []
                if boundary and document['recognition_call_count']+2<=MAX_RECOGNITION_CALLS:
                    name_crop,expected_name = boundary
                    observe(name_crop,'enlarged',name_observations)
                    observe(name_crop,'contrast',name_observations)
                confirmed = bool(boundary and name_boundary_confirmed(boundary[1],name_observations))
                entry['name_boundary'] = {'confirmed':confirmed,'observations':name_observations,
                                          'original_name':row['cells'].get('name')}
                if confirmed:
                    name_reading = next(o for o in name_observations if o['confident'])
                    row['cells']['name'] = name_reading['text']
                    row['fields']['name'] = name_reading['blocks']
                    row['alignment_ok'] = alignment_before
                else:
                    row['alignment_ok'] = False
                    entry['requires_boundary_review'] = True
        elif len(alternatives)>1 or (old_valid and alternatives and canonical(field,original) not in alternatives):
            row['alignment_ok'] = False
            entry['conflict'] = True
        document['retry_count'] += 1
    document['retry_budget'] = {'max_fields':MAX_RETRIES,'max_calls':MAX_RECOGNITION_CALLS,
                                'exhausted':document['recognition_call_count']>=MAX_RECOGNITION_CALLS}
    document['metrics'] = parse_report_document(document)
    for row in document['rows']:
        row.setdefault('original_text',row['text'])
        row['text'] = ' | '.join(row['cells'].get(k,'') for k in ('name','code','result','unit','reference'))
    update_coverage(document)


def parse_report_document(document):
    from core.report_fields import parse_cells
    metrics = []
    for index, row in enumerate(document['rows']):
        if 'cells' not in row:
            # Existing snapshots keep their old evidence. Never silently claim a
            # legacy flattened line has the new table/column verification.
            for metric in parse_metrics(row['text']):
                if metric.get('code'):
                    metric.update(status='unparsed', needs_review=True,
                                  verification_reason='旧版文本证据未包含已核对的单元格对应关系',
                                  source_line=index, source_lines=[index], source_blocks=row.get('blocks',[]),
                                  ocr_confidence=row.get('confidence'))
                    metrics.append(metric)
            continue
        metric = parse_cells(row['cells'], evidence=row['fields'], alignment_ok=row['alignment_ok'])
        if metric:
            metric.update(source_line=index, source_lines=[index], table_id=row['table_id'],
                          ocr_pipeline_version=VERSION, alignment=row['alignment'])
            metrics.append(metric)
    return metrics


def report_metrics(report):
    """One persisted result for upload, history and family sync; legacy reports still work."""
    details = getattr(report, "ocr_details", None)
    if isinstance(details, dict) and isinstance(details.get("metrics"), list):
        return deepcopy(details["metrics"])
    return parse_metrics(report.ocr_text or "")
