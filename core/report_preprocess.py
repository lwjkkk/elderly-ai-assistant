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


def rotation(image, clockwise):
    import cv2
    import numpy as np
    h,w = image.shape[:2]
    if clockwise==90:
        return cv2.rotate(image,cv2.ROTATE_90_CLOCKWISE),np.array([[0,-1,h-1],[1,0,0],[0,0,1]],dtype=float)
    if clockwise==180:
        return cv2.rotate(image,cv2.ROTATE_180),np.array([[-1,0,w-1],[0,-1,h-1],[0,0,1]],dtype=float)
    if clockwise==270:
        return cv2.rotate(image,cv2.ROTATE_90_COUNTERCLOCKWISE),np.array([[0,1,0],[-1,0,w-1],[0,0,1]],dtype=float)
    raise ValueError('Only right-angle rotation candidates are supported')


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


def page_warp(image):
    """Only a clear, convex, complete quadrilateral is a perspective candidate."""
    import cv2
    import numpy as np
    h,w = image.shape[:2]
    scale = min(1,1000/max(h,w))
    small = cv2.resize(image,None,fx=scale,fy=scale) if scale<1 else image
    gray = cv2.cvtColor(small,cv2.COLOR_BGR2GRAY)
    _,mask = cv2.threshold(cv2.GaussianBlur(gray,(5,5),0),0,255,cv2.THRESH_BINARY+cv2.THRESH_OTSU)
    contours,_ = cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    for contour in sorted(contours,key=cv2.contourArea,reverse=True)[:3]:
        approx = cv2.approxPolyDP(contour,.02*cv2.arcLength(contour,True),True)
        area = cv2.contourArea(approx)/(small.shape[0]*small.shape[1])
        if len(approx)!=4 or not .35<area<.96 or not cv2.isContourConvex(approx):
            continue
        points = approx.reshape(4,2).astype(float)/scale
        # Angle ordering handles either contour winding without duplicate corners.
        center = points.mean(axis=0)
        points = points[np.argsort(np.arctan2(points[:,1]-center[1],points[:,0]-center[0]))]
        points = np.roll(points,-np.argmin(points.sum(axis=1)),axis=0)
        tl,tr,br,bl = points
        width = int(max(np.linalg.norm(tr-tl),np.linalg.norm(br-bl)))
        height = int(max(np.linalg.norm(bl-tl),np.linalg.norm(br-tr)))
        if min(width,height)<200:
            continue
        matrix = cv2.getPerspectiveTransform(points.astype('float32'),np.array([[0,0],[width-1,0],[width-1,height-1],[0,height-1]],dtype='float32'))
        return cv2.warpPerspective(image,matrix,(width,height),borderValue=(255,255,255)),matrix,'page_perspective'
    return None


def select_view(image, initial, recognize, build):
    import cv2
    import numpy as np
    current,document = image,initial
    forward = np.eye(3)
    metadata = {'selected':'original','candidates':[],'orientation_probe_calls':0,'additional_full_image_calls':0}
    if not document['tables']:
        probes = []
        metadata['orientation_probes_full_resolution'] = True
        for degrees in (90,180,270):
            rotated,matrix = rotation(image,degrees)
            metadata['orientation_probe_calls'] += 1
            try:
                candidate = build(recognize(rotated),rotated.shape[1],rotated.shape[0])
                probes.append((quality(candidate),degrees,rotated,matrix,candidate))
                metadata['candidates'].append({'view':f'rotation_probe_{degrees}','quality':quality(candidate)})
            except Exception:
                metadata['candidates'].append({'view':f'rotation_probe_{degrees}','failed':True})
        if probes:
            best = max(x[0] for x in probes)
            winners = [p for p in probes if p[0]==best]
            if best>quality(initial) and len(winners)==1:
                _,degrees,rotated,matrix,candidate = winners[0]
                accepted = preserves(initial,candidate)
                metadata['candidates'].append({'view':f'rotation_{degrees}','quality':quality(candidate),'accepted':accepted})
                if accepted:
                    current,document,forward = rotated,candidate,matrix
                    metadata['selected'] = f'rotation_{degrees}'
    metrics = document.get('metrics',[])
    weak = not metrics or quality(document)[1]<len(metrics)*.7 or any(m.get('result') is None and m.get('lo') is not None for m in metrics)
    if weak:
        view = table_crop(current,document)
        if view is None and (not metrics or quality(document)[1]<len(metrics)*.5):
            view = page_warp(current)
        if view is not None:
            transformed,matrix,label = view
            metadata['additional_full_image_calls'] += 1
            try:
                candidate = build(recognize(transformed),transformed.shape[1],transformed.shape[0])
                accepted = quality(candidate)>quality(document) and preserves(document,candidate)
                metadata['candidates'].append({'view':label,'quality':quality(candidate),'accepted':accepted})
                if accepted:
                    current,document,forward = transformed,candidate,matrix@forward
                    metadata['selected'] += '+'+label
            except Exception:
                metadata['candidates'].append({'view':label,'failed':True})
    metadata['original_quality'] = quality(initial)
    metadata['selected_quality'] = quality(document)
    return current,document,forward,metadata


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
