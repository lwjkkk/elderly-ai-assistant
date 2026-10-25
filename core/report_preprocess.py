"""Report-only candidate views, with original evidence and coordinate recovery."""
import re
from copy import deepcopy


def quality(document):
    metrics = document.get('metrics',[])
    usable = sum(m.get('result') is not None and m.get('range_text') is not None for m in metrics)
    verified = sum(m.get('status') in ('normal','high','low') for m in metrics)
    return (usable,verified)


def preserves(original, candidate):
    """Do not trade an already verified value/range/unit for more candidates."""
    def key(value):return re.sub(r'[^A-Z0-9\u4e00-\u9fff#%]','',value.upper())
    by_key = {}
    for m in candidate.get('metrics',[]):by_key.setdefault(key(m['code']),[]).append(m)
    for m in original.get('metrics',[]):
        if m['status'] not in ('normal','high','low'):
            continue
        matches = by_key.get(key(m['code']),[])
        if len(matches)!=1:
            return False
        other = matches[0]
        if any(m.get(k)!=other.get(k) for k in ('result','unit','lo','hi','lo_inclusive','hi_inclusive')):
            return False
    return True


def table_crop(image, document):
    import numpy as np
    points = [p for row in document['rows'] for role in ('name','code','result','reference','unit')
              for b in row['fields'].get(role,[]) for p in b['polygon']]
    if not points or not document['tables']:
        return None
    h,w = image.shape[:2]
    xs,ys = zip(*points)
    top = min(t['bbox'][1] for t in document['tables'])
    pad = max(12,int(h*.015))
    x0,y0 = max(0,int(min(xs))-pad),max(0,int(min(top,min(ys)))-pad)
    x1,y1 = min(w,int(max(xs))+pad),min(h,int(max(ys))+pad)
    if (x1-x0)*(y1-y0)>.60*w*h or x1-x0<200 or y1-y0<60:
        return None
    return image[y0:y1,x0:x1],np.array([[1,0,-x0],[0,1,-y0],[0,0,1]],dtype=float),'table_crop'


def orientation_issue(document):
    """Use existing text boxes only; never rotate or run orientation OCR probes."""
    from math import atan,degrees
    from statistics import median
    vertical = 0
    eligible = 0
    angles = []
    for block in document.get('raw_blocks',[]):
        polygon = block.get('polygon',[])
        if len(polygon)<4 or len(block.get('text','').strip())<3:
            continue
        xs,ys = zip(*polygon)
        width,height = max(xs)-min(xs),max(ys)-min(ys)
        if max(width,height)>=3*max(1,min(width,height)):
            eligible += 1
            vertical += height>width*2.5
        dx,dy = polygon[1][0]-polygon[0][0],polygon[1][1]-polygon[0][1]
        if abs(dx)>=50 and width>height*2:
            angles.append(degrees(atan(dy/dx)))
    if eligible>=4 and vertical/eligible>.6:
        return {'code':'vertical_text','message':'报告文字横放或方向不正，请摆正后重新拍摄'}
    if len(angles)>=4 and abs(median(angles))>10:
        return {'code':'excessive_tilt','message':'报告倾斜明显，请正对报告重新拍摄','median_angle':round(median(angles),2)}
    return None


def select_view(image, initial, recognize, build):
    import numpy as np
    document = initial
    forward = np.eye(3)
    issue = orientation_issue(initial)
    metadata = {'selected':'original','candidates':[],'orientation_probe_calls':0,
                'additional_full_image_calls':0,'rotation_policy':'retake_no_rotation',
                'orientation_status':'incorrect' if issue else 'unconfirmed' if not document['tables'] else 'no_issue_detected'}
    if issue:
        metadata['orientation_issue'] = issue
    # No upright table: ask for a better photo instead of repeatedly rotating,
    # rectifying or re-recognizing the full image.
    if issue or not document['tables']:
        metadata['original_quality'] = metadata['selected_quality'] = quality(initial)
        return image,document,forward,metadata
    metrics = document.get('metrics',[])
    weak = not metrics or quality(document)[1]<len(metrics)*.7 or any(m.get('result') is None and m.get('lo') is not None for m in metrics)
    if weak:
        view = table_crop(image,document)
        if view is not None:
            transformed,matrix,label = view
            metadata['additional_full_image_calls'] += 1
            try:
                candidate = build(recognize(transformed),transformed.shape[1],transformed.shape[0])
                accepted = quality(candidate)>quality(document) and preserves(document,candidate)
                metadata['candidates'].append({'view':label,'quality':quality(candidate),'accepted':accepted})
                if accepted:
                    image,document,forward = transformed,candidate,matrix
                    metadata['selected'] += '+'+label
            except Exception:
                metadata['candidates'].append({'view':label,'failed':True})
    metadata['original_quality'] = quality(initial)
    metadata['selected_quality'] = quality(document)
    return image,document,forward,metadata


def restore_coordinates(document, forward, original_shape):
    import numpy as np
    inverse = np.linalg.inv(forward)
    def point(x,y):
        p = inverse@np.array([x,y,1.0]);return [float(p[0]/p[2]),float(p[1]/p[2])]
    # Duplicate block references are transformed from immutable input each time.
    def convert(value):
        if isinstance(value,list):return [convert(v) for v in value]
        if not isinstance(value,dict):return value
        out = {k:convert(v) for k,v in value.items()}
        if isinstance(value.get('polygon'),list):
            out['polygon'] = [point(x,y) for x,y in value['polygon']]
        if 'cx' in value and 'cy' in value:
            out['cx'],out['cy'] = point(value['cx'],value['cy'])
            if 'polygon' in out and len(out['polygon'])>=4:
                out['h'] = float(np.linalg.norm(np.array(out['polygon'][3])-out['polygon'][0]))
        for key in ('bbox','crop'):
            box = value.get(key)
            if isinstance(box,list) and len(box)==4:
                x0,y0,x1,y1=box
                polygon=[point(x0,y0),point(x1,y0),point(x1,y1),point(x0,y1)]
                out[key+'_polygon']=polygon
                out[key]=[min(p[0] for p in polygon),min(p[1] for p in polygon),max(p[0] for p in polygon),max(p[1] for p in polygon)]
        if 'x' in value and 'y' in value and 'role' not in value:
            out['x'],out['y']=point(value['x'],value['y'])
        return out
    source = deepcopy(document)
    for finding in source.get('coverage',{}).get('findings',[]):
        if 'y_range' in finding:
            t = source['tables'][finding['table_id']]
            x0,_,x1,_=t['bbox'];y0,y1=finding.pop('y_range')
            finding['polygon']=[[x0,y0],[x1,y0],[x1,y1],[x0,y1]]
    out = convert(source)
    out['processing_dimensions'] = {'width':document['width'],'height':document['height']}
    out['width'],out['height'] = int(original_shape[1]),int(original_shape[0])
    out['coordinate_space'] = 'original_image_pixels'
    out['diagnostic_coordinate_space'] = 'processing_image_pixels'
    out['processing_to_original'] = inverse.tolist()
    return out
