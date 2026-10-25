"""Operational retake gate; these thresholds are not medical accuracy scores."""
REQUIREMENTS = [
    '一次拍摄一页报告，保留完整表头、项目、结果、单位和参考范围；原件本身没有的字段无需补写。',
    '将报告摆正、尽量铺平，镜头正对纸面，减少倾斜和弯曲。',
    '光线均匀，避开反光、阴影、手指和其他遮挡。',
    '靠近拍摄并对焦，确保放大后数字、小数点和单位仍清楚，上传清晰原图。',
]


class ReportRetakeRequired(ValueError):
    def __init__(self, document):
        self.document = document
        self.detail = document['retake']
        super().__init__(self.detail['message'])


def assess_report(document):
    metrics = document.get('metrics',[])
    count = len(metrics)
    extracted = sum(m.get('result') is not None for m in metrics)
    reliable = 0
    for m in metrics:
        evidence = m.get('field_evidence',{}).get('result',[])
        if (m.get('result') is not None and evidence
                and all(b.get('confidence') is not None and b['confidence']>=.90 for b in evidence)
                and 'alignment' not in m.get('review_fields',[])):
            reliable += 1
    reasons = []
    if not document.get('raw_blocks'):
        reasons.append({'code':'no_text','message':'没有识别到可用文字'})
    elif not document.get('tables'):
        reasons.append({'code':'no_table','message':'未能定位包含项目、结果与参考条件的报告表格'})
    elif not count or not extracted:
        reasons.append({'code':'no_results','message':'未能提取可用的检测结果'})
    elif not reliable:
        reasons.append({'code':'no_reliable_results','message':'检测结果均缺少足够清晰且配对明确的识别证据'})
    elif count>=5 and reliable/count<.5:
        reasons.append({'code':'majority_unreadable','message':'多数项目的结果缺失、置信不足或行归属不明确'})
    required = bool(reasons)
    review = sum(m.get('needs_review',True) for m in metrics)
    document['recognition_status'] = 'retake_required' if required else 'partial' if review else 'usable'
    document['retake_required'] = required
    document['quality_summary'] = {'detected_metrics':count,'extracted_results':extracted,
                                   'clear_aligned_results':reliable,'needs_review':review,
                                   'threshold_scope':'operational_not_calibrated_accuracy'}
    message = ('本次未能可靠识别报告，请重新拍摄清晰、完整的报告图片。' +
               ('原因：'+'；'.join(r['message'] for r in reasons)+'。' if reasons else ''))
    document['retake'] = {'required':required,'code':'report_retake_required' if required else None,
                           'message':message if required else '', 'reasons':reasons,
                           'requirements':list(REQUIREMENTS)}
    return document
