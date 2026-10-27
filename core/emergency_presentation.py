"""Keep reported words separate from risk groups; labels are not symptom findings."""

RISK_LABELS = {
    'chest_pain': '胸部不适相关危险信号',
    'breath': '呼吸相关危险信号',
    'consciousness': '意识或晕厥相关危险信号',
    'stroke': '卒中相关危险信号',
    'bleeding': '出血相关危险信号',
    'choking': '气道梗阻相关危险信号',
    'severe_headache': '头痛相关危险信号',
    'severe_allergy': '过敏相关危险信号',
    'emergency_other': '其他需立即求助的危险信号',
}


def category_labels(keys):
    return list(dict.fromkeys(RISK_LABELS.get(key, '需立即求助的危险信号')
                              for key in keys))


def emergency_metadata(question, keys):
    if not keys:
        return {}
    return {'reported_question': question, 'emergency_labels': category_labels(keys)}
