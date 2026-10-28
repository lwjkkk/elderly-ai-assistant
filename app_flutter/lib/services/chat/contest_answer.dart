import 'dart:convert';

Map<String, dynamic> answerMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

bool hasStructuredAnswer(Map<String, dynamic> data) =>
    answerMap(data['parts']).isNotEmpty ||
    answerMap(data['elder_view']).isNotEmpty ||
    answerMap(data['family_view']).isNotEmpty;

bool answerDefaultsToDetailedView(Map<String, dynamic> data) =>
    data['role'] == 'family';

bool answerIsEmergency(Map<String, dynamic> data) =>
    data['emergency'] == true ||
    answerMap(data['triage'])['status'] == 'urgent';

bool answerNeedsUrgentReview(Map<String, dynamic> data) =>
    !answerIsEmergency(data) &&
    (data['urgent_review_required'] == true ||
        answerMap(data['triage'])['status'] == 'uncertain');

String familyNotificationExplanation(Map<String, dynamic> data) =>
    switch (data['family_notification_status']) {
      'profile_incomplete' => '出生年月资料未完善，本次未向家属披露。',
      'sharing_disabled' => '健康共享已关闭，本次未向家属披露。',
      'no_recipients' => '当前没有可接收提醒的授权家属。',
      'queued' => '家属提醒已交后台处理，不代表手机已送达。',
      _ => '',
    };

String answerFallbackLabel(Map<String, dynamic> data) {
  const labels = {
    'urgent_symptoms': '危险信号，优先立即求助',
    'medication_boundary': '个人用药决策需医生或药师确认',
    'medication_output_removed': '已拦截不合适的药物建议',
    'individual_medical_limits': '个人医疗条件尚未确认',
    'platform_requires_confirmation': '需要确认机型或补充核验资料',
    'device_capability_unverified': '设备能力不能保证',
    'regional_policy_unverified': '缺少当地当期政策依据',
    'specific_procedure_missing': '缺少已核验的专项操作流程',
    'realtime_data_unavailable': '当前没有实时查询依据',
    'source_fabrication_refused': '不提供未经核实的来源',
    'private_fact_unavailable': '无法得知个人私密信息',
    'clarification_required': '需要补充具体对象',
    'no_relevant_chunks': '未找到直接相关片段',
    'vector_index_unavailable': '向量索引不可用，已回退检索',
  };
  return labels[(data['fallback_reason'] ?? '').toString()] ?? '';
}

String answerOriginLabel(Map<String, dynamic> data) =>
    switch (data['answer_origin']) {
      'safety_rule' => '安全规则提示',
      'llm' => 'AI生成回答',
      'error' => '回答服务返回错误',
      _ => '',
    };

Map<String, String> answerEmergencySections(Map<String, dynamic> data,
    {bool detailed = false}) {
  final views = [
    if (detailed) data['family_view'],
    if (!detailed) data['elder_view'],
    data['parts'],
    data['view'],
    if (detailed) data['elder_view'],
    if (!detailed) data['family_view'],
  ].map(answerMap).where((view) => view.isNotEmpty);
  String action = '';
  String seek = '';
  for (final view in views) {
    action = action.isNotEmpty
        ? action
        : (view['next_step'] ?? view['advice'] ?? '').toString().trim();
    seek = seek.isNotEmpty ? seek : (view['seek'] ?? '').toString().trim();
  }
  if (action.isEmpty) action = answerOriginalText(data);
  return {'action': action, 'seek': seek};
}

List<String> answerEmergencyTypeLabels(Map<String, dynamic> data) {
  final supplied = data['emergency_labels'];
  if (supplied is List) {
    final labels = supplied
        .whereType<String>()
        .where((label) => label.trim().isNotEmpty)
        .toSet()
        .toList();
    if (labels.isNotEmpty) return labels;
  }
  if (supplied is String && supplied.trim().isNotEmpty) {
    return [supplied.trim()];
  }
  const labels = {
    'choking': '气道梗阻相关危险信号',
    'stroke': '卒中相关危险信号',
    'chest_pain': '胸部不适相关危险信号',
    'breath': '呼吸相关危险信号',
    'consciousness': '意识或晕厥相关危险信号',
    'bleeding': '出血相关危险信号',
    'severe_headache': '头痛相关危险信号',
    'severe_allergy': '过敏相关危险信号',
    'emergency_other': '其他需立即求助的危险信号',
  };
  final types = data['emergency_types'];
  if (types is! List) return const [];
  return types
      .map((type) => labels[type.toString()] ?? '紧急情况')
      .toSet()
      .toList();
}

String answerText(Map<String, dynamic> data, {bool detailed = false}) {
  final sections = answerMap(detailed
      ? data['family_view'] ?? data['parts']
      : data['elder_view'] ?? data['view']);
  if (sections.isEmpty) {
    return _appendAnswerContext((data['answer'] ?? '').toString(), data);
  }
  // v3 carries the selected body's own labels/text; never append steps again.
  final text = (sections['text'] ?? '').toString().trim();
  if (text.isNotEmpty) return _withoutFooter(text, data);
  final supplied = sections['sections'];
  if (supplied is List && supplied.isNotEmpty) {
    final body = supplied
        .whereType<Map>()
        .map((section) {
          final label = (section['label'] ?? '').toString().trim();
          final content = (section['content'] ?? '').toString().trim();
          return content.isEmpty
              ? ''
              : label.isEmpty
                  ? content
                  : '$label\n$content';
        })
        .where((text) => text.isNotEmpty)
        .join('\n\n');
    if (body.isNotEmpty) return _withoutFooter(body, data);
  }
  // 新协议为关注点、通俗解释、下一步和就医提醒；旧协议仍按原字段展示。
  final labels = sections.containsKey('meaning') ||
          sections.containsKey('concern') ||
          sections.containsKey('next_step')
      ? const {
          'concern': '关注什么',
          'meaning': '是什么意思',
          'next_step': '下一步怎么办',
          'seek': '何时就医'
        }
      : const {'conclusion': '关注什么', 'advice': '下一步怎么办', 'seek': '何时就医'};
  final body = [
    for (final key in labels.keys)
      if ((sections[key] ?? '').toString().trim().isNotEmpty)
        '${labels[key]}\n${sections[key]}',
  ].join('\n\n');
  return _withoutFooter(
      body.isEmpty ? (data['answer'] ?? '').toString() : body, data);
}

bool hasDistinctAnswerViews(Map<String, dynamic> data) {
  if (data['views_distinct'] == false) return false;
  final elder = answerMap(data['elder_view'] ?? data['view']);
  final family = answerMap(data['family_view']);
  if (elder.isEmpty || family.isEmpty) return false;
  final short = answerText(data);
  final detailed = answerText(data, detailed: true);
  return short.isNotEmpty && detailed.isNotEmpty && short != detailed;
}

String _withoutFooter(String text, Map<String, dynamic> data) {
  var body = text.trim();
  for (final value in [
    data['display_notice'],
    data['disclaimer'],
    answerMap(data['answer_footer'])['safety_notice']
  ]) {
    final notice = (value ?? '').toString().trim();
    if (notice.isNotEmpty && body.endsWith(notice)) {
      body = body.substring(0, body.length - notice.length).trim();
    }
  }
  return body;
}

String _appendAnswerContext(String answer, Map<String, dynamic> data) {
  answer = _withoutFooter(answer, data);
  final steps = data['steps'] is List
      ? (data['steps'] as List)
          .map((step) => step.toString().trim())
          .where((step) => step.isNotEmpty && !answer.contains(step))
          .toList()
      : <String>[];
  return _withoutFooter(
      [
        answer,
        if (steps.isNotEmpty)
          '步骤：\n${steps.map((step) => '• $step').join('\n')}',
      ].where((part) => part.isNotEmpty).join('\n\n'),
      data);
}

/// Footer is separate from body/TTS and only exposes an explicit UI whitelist.
Map<String, dynamic> answerFooter(Map<String, dynamic> data) {
  final footer = answerMap(data['answer_footer']);
  final references = answerMap(footer['references']);
  final rawItems = references['items'];
  final groups = <String, Map<String, dynamic>>{};
  final items = rawItems is List ? rawItems : answerSources(data);
  if (references['visible'] != false &&
      data['answer_origin'] != 'safety_rule' &&
      data['answer_origin'] != 'error') {
    for (final raw in items.whereType<Map>()) {
      final source = answerMap(raw);
      final excerpts = source['excerpts'] is List
          ? (source['excerpts'] as List)
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toList()
          : [(source['excerpt'] ?? '').toString().trim()]
              .where((s) => s.isNotEmpty)
              .toList();
      if (excerpts.isEmpty) continue;
      final title =
          (source['title'] ?? source['source'] ?? '知识库参考片段').toString();
      final key =
          (source['document_id'] ?? source['source'] ?? title).toString();
      final item = groups.putIfAbsent(
          key,
          () => {
                'title': title,
                'excerpts': <String>[],
                'source_url': source['source_url'],
                'applicability': answerMap(source['applicability']).isNotEmpty
                    ? answerMap(source['applicability'])
                    : {
                        for (final key in [
                          'region',
                          'platform',
                          'updated_at',
                          'valid_until'
                        ])
                          if (source[key] != null &&
                              source[key] != '' &&
                              source[key] != '通用')
                            key: source[key]
                      },
              });
      for (final excerpt in excerpts) {
        if (!(item['excerpts'] as List).contains(excerpt)) {
          (item['excerpts'] as List).add(excerpt);
        }
      }
    }
  }
  return {
    'items': groups.values.toList(),
    'notice': groups.isEmpty
        ? ''
        : (references['notice'] ?? '参考资料用于核对回答依据，不代表专业认证。').toString(),
    'safety_notice': (footer['safety_notice'] ??
            data['display_notice'] ??
            data['disclaimer'] ??
            '')
        .toString()
        .trim(),
  };
}

String answerOriginalText(Map<String, dynamic> data) =>
    (data['answer'] ?? '').toString().trim();

List<Map<String, dynamic>> answerSources(Map<String, dynamic> data) =>
    data['sources'] is List
        ? (data['sources'] as List).whereType<Map>().map(answerMap).toList()
        : [];

Map<String, dynamic> decodeAnswer(String? encoded) {
  try {
    return answerMap(jsonDecode(encoded ?? ''));
  } catch (_) {
    return {};
  }
}

// 只路由明确的测量记录；健康咨询仍留在问答流程。
bool looksLikeVitalRecord(String text) {
  if (RegExp(r'怎么|如何|正常吗|怎么办|为什么|多少才|能不能|可以吗|\?|？').hasMatch(text)) {
    return false;
  }
  return RegExp(r'血压|高压|低压|收缩压|舒张压|血糖|心率|体重').hasMatch(text) &&
      RegExp(r'\d|测了|量了|记录|记一下').hasMatch(text);
}
