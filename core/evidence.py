"""Shared presentation contract for references actually used during generation.

Knowledge-base retrieval and external verification are separate facts. A missing
URL must never hide an otherwise traceable knowledge-base excerpt.
"""
from copy import deepcopy
from urllib.parse import urlsplit


def safety_notice(module: str) -> str:
    if module == 'health':
        return '健康科普参考，不能替代医生面诊；请勿自行用药。'
    if module == 'services':
        return '具体办理条件以当地主管部门和受理机构规定为准。'
    if module == 'phone':
        return '操作入口可能随手机型号和软件版本变化。'
    return '请结合实际情况使用，注意人身、财产和个人信息安全。'


def _safe_url(value):
    if not isinstance(value, str):
        return None
    try:
        url = urlsplit(value.strip())
        if url.scheme.lower() in ('http', 'https') and url.hostname and not url.username and not url.password:
            return value.strip()
    except ValueError:
        pass
    return None


def build_footer(sources: list[dict], module: str) -> dict:
    """Only user-facing reference content: no scores, hashes or pipeline labels."""
    groups = {}
    for source in sources:
        key = source.get('document_id') or source.get('source') or (source['title'], source.get('source_url'))
        if key not in groups:
            groups[key] = {
                'title': source['title'], 'excerpts': [],
                'source_url': _safe_url(source.get('source_url')),
                'applicability': {key: source[key] for key in ('region', 'platform', 'updated_at', 'valid_until')
                                  if source.get(key) and source[key] != '通用'},
            }
        excerpt = source['excerpt'].strip()
        if excerpt not in groups[key]['excerpts']:
            groups[key]['excerpts'].append(excerpt)
    return {
        'schema_version': 1,
        'references': {
            'visible': bool(groups), 'expanded': False,
            'label': '查看知识库依据', 'items': list(groups.values()),
            'notice': ('参考资料用于核对回答依据，不代表专业诊断或认证。' if module == 'health'
                       else '参考资料用于核对回答依据，请结合实际情况使用。') if groups else '',
        },
        'safety_notice': safety_notice(module),
        'speak_by_default': False,
    }


def attach_evidence(result: dict) -> dict:
    result = dict(result)
    raw_sources = result.get('sources') or []
    if not isinstance(raw_sources, list):
        raw_sources = []
    sources = [deepcopy(s) for s in raw_sources
               if isinstance(s, dict) and isinstance(s.get('excerpt'), str) and s['excerpt'].strip()]
    # Safety/error replies do not use the discarded model context as evidence.
    if result.get('answer_origin') in ('safety_rule', 'error'):
        sources = []
    has_evidence = bool(sources)
    externally_reviewed = has_evidence and all(
        s.get('verification_status') == 'documented_review' for s in sources)
    for source in sources:
        source['title'] = source.get('title') or source.get('source') or '知识库参考片段'
        source['has_external_url'] = bool(source.get('source_url'))
    module = result.get('module') or ('health' if 'advice_text' in result else 'daily_life')
    result.update(
        sources=sources,
        has_evidence=has_evidence,
        knowledge_base_hit=has_evidence,
        evidence_status=('sufficient' if externally_reviewed and
                         result.get('retrieval_channel') != 'keyword_fallback'
                         else 'insufficient' if has_evidence else 'none'),
        # Diagnostic metadata remains available separately, never footer prose.
        evidence_notice='',
        answer_footer=build_footer(sources, module),
        display_notice=safety_notice(module),
        disclaimer=safety_notice(module),
        evidence_card={
            'visible': has_evidence,
            'title': '知识库参考',
            'items': deepcopy(sources),
            'notice': ('以下片段供核对回答依据，知识库参考不代表专业认证。'
                       if has_evidence else ''),
        },
    )
    return result
