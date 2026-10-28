import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'medication/medication_time.dart';
import 'medication/medication_name.dart';
import 'health/vital_validation.dart';
import 'reports/report_retake.dart';

/// B 前端接口层：严格按 C v2.0《API接口文档》实现，以 backend 分支为准。
class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json; charset=utf-8',
  ));

  static Dio get dio => _dio;
  static String get baseUrl => AppConfig.baseUrl;
  static const disclaimer = '本内容仅供健康科普参考，不构成医疗诊断或用药建议。具体诊疗请遵医嘱，如有急症请立即拨打120。';

  static Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString('token');
    if (t != null && t.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $t';
    }
    return t;
  }

  static Future<String?> getRole() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('role');
  }

  static Future<int?> getUserId() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('user_id');
  }

  /// 家属端调用健康接口必须带的 elder_id：优先用已选中的绑定长辈。
  static Future<int?> getElderId() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('elder_id');
  }

  static Future<void> setElderId(int id) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('elder_id', id);
  }

  static Future<void> saveAuth(String token, String role,
      {int? userId, String? nickname}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token);
    await p.setString('role', role);
    if (userId != null) await p.setInt('user_id', userId);
    if (nickname != null) await p.setString('nickname', nickname);
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  static Future<String?> getNickname() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('nickname');
  }

  static Future<void> clearAuth() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('role');
    await p.remove('user_id');
    await p.remove('nickname');
    await p.remove('elder_id');
    _dio.options.headers.remove('Authorization');
  }

  /// 本人模式不传 elder_id；长辈模式必须明确绑定对象，避免误读家属本人数据。
  static Future<Map<String, dynamic>> withElder(
      [Map<String, dynamic>? extra, bool mine = false]) async {
    final m = Map<String, dynamic>.from(extra ?? {});
    final role = await getRole();
    if (role == 'family' && mine) m.remove('elder_id');
    if (role == 'family' && !mine) {
      var eid = await getElderId();
      if (eid == null) {
        final binds = await bindList();
        for (final b in binds) {
          final bm = b is Map
              ? Map<String, dynamic>.from(b as Map)
              : <String, dynamic>{};
          if (bm['status'] == 'active' && bm['elder_id'] is int) {
            eid = bm['elder_id'] as int;
            await setElderId(eid);
            break;
          }
        }
      }
      if (eid == null) throw StateError('请先绑定长辈，再查看长辈记录');
      m['elder_id'] = eid;
    }
    return m;
  }

  // ---------- 5.1 鉴权 ----------
  static Future<void> register(
      {required String phone,
      required String password,
      required String nickname,
      required String role}) async {
    await _dio.post('/api/auth/register', data: {
      'phone': phone,
      'password': password,
      'nickname': nickname,
      'role': role,
    });
  }

  /// v2.0 登录响应顶层即有 role/nickname，直接存，不再信任调用方传入的 role。
  static Future<Map<String, dynamic>> login(
      {required String phone, required String password}) async {
    final res = await _dio.post('/api/auth/login', data: {
      'phone': phone,
      'password': password,
    });
    final d = Map<String, dynamic>.from(res.data);
    await saveAuth(
        (d['access_token'] ?? '').toString(), (d['role'] ?? 'elder').toString(),
        userId: (d['user_id'] as num?)?.toInt(),
        nickname: (d['nickname'] ?? '').toString());
    return d;
  }

  static Future<void> refresh() async {
    final res = await _dio.post('/api/auth/refresh');
    final d = Map<String, dynamic>.from(res.data);
    await saveAuth((d['access_token'] ?? '').toString(),
        (d['role'] ?? await getRole() ?? 'elder').toString(),
        nickname: (d['nickname'] ?? '').toString());
  }

  // ---------- 5.2 绑定 ----------
  /// 短信验证码登录（后端 /api/auth/sms/* 就绪后生效，UI 已预留）。
  static Future<void> sendSmsCode(String phone) async {
    await _dio.post('/api/auth/send_sms_code', data: {'phone': phone});
  }

  static Future<Map<String, dynamic>> loginSms(
      {required String phone, required String code}) async {
    final res = await _dio
        .post('/api/auth/login_by_code', data: {'phone': phone, 'code': code});
    final d = Map<String, dynamic>.from(res.data as Map);
    final token = (d['token'] ?? d['access_token'] ?? '').toString();
    await saveAuth(token, (d['role'] ?? 'elder').toString(),
        userId: d['user_id'] is int ? d['user_id'] as int : null,
        nickname: (d['nickname'] ?? '').toString());
    return {'role': d['role'] ?? 'elder'};
  }

  static Future<String> createInvite() async {
    final res = await _dio.post('/api/bind/invite');
    return res.data['invite_code'].toString();
  }

  static Future<Map<String, dynamic>> acceptInvite(String code) async {
    final res =
        await _dio.post('/api/bind/accept', data: {'invite_code': code});
    final d = Map<String, dynamic>.from(res.data);
    if (d['elder_id'] is int) await setElderId(d['elder_id'] as int);
    return d;
  }

  /// v2.0 对方昵称字段为 other_nickname。
  static Future<List> bindList() async {
    final res = await _dio.get('/api/bind/list');
    final d = res.data;
    return d is List ? d : [];
  }

  static Future<List> familyMessages(int bindingId) async {
    final res = await _dio.get('/api/messages/$bindingId');
    return res.data is List ? res.data as List : [];
  }

  static Future<Map<String, dynamic>> uploadFamilyAudio(int bindingId,
      List<int> bytes, String filename, int seconds, String clientId) async {
    final result = await _dio.post('/api/messages/$bindingId/audio',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: filename),
          'duration': seconds,
          'client_id': clientId
        }),
        options: Options(receiveTimeout: const Duration(minutes: 2)));
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Uint8List> familyAudioBytes(String url) async {
    final result = await _dio.get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(result.data ?? []);
  }

  static Future<String> transcribeFamilyAudio(int bindingId, int id) async {
    final result = await _dio.post('/api/messages/$bindingId/$id/transcribe',
        options: Options(receiveTimeout: const Duration(minutes: 2)));
    return (result.data['text'] ?? '').toString();
  }

  static Future<void> deleteFamilyMessage(int bindingId, int id) async {
    await _dio.delete('/api/messages/$bindingId/$id');
  }

  static Future<Map<String, dynamic>> sendFamilyMessage(
      int bindingId, String kind, Map<String, dynamic> content) async {
    final res = await _dio.post('/api/messages/$bindingId',
        data: {'kind': kind, 'content': content});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// 把报错翻译成长辈能看懂的话，各页面直接用。
  static int? statusOf(Object e) {
    if (e is DioException) return e.response?.statusCode;
    return null;
  }

  static dynamic _errorData(DioException e) {
    final data = e.response?.data;
    if (data is List<int>) {
      try {
        return jsonDecode(utf8.decode(data));
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  /// 后端 detail 原文（用于 400 这类业务提示，直接展示不加"失败"前缀）。
  static String? errorDetail(Object e) {
    if (e is DioException) {
      final data = _errorData(e);
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (data is String && data.isNotEmpty) return data;
    }
    return null;
  }

  static String friendly(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      dynamic data = _errorData(e);
      final detail = data is Map && data['detail'] != null
          ? data['detail'].toString()
          : '';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '网络超时，请检查网络后重试';
      }
      if (e.type == DioExceptionType.connectionError) {
        return '连不上服务器，请确认后端已启动且地址正确';
      }
      switch (code) {
        case 500:
          if (detail.contains('识别服务') || detail.contains('OCR')) {
            return '图片识别服务暂不可用，请稍后重试';
          }
          if (detail.contains('PDF')) return 'PDF 导出服务暂不可用，请稍后重试';
          break;
        case 400:
          return detail.isNotEmpty ? detail : '请求不对，请检查输入内容';
        case 401:
          return '手机号或密码不对（或登录已过期，请重新登录）';
        case 403:
          return '没有权限，请先完成长辈与家属绑定';
        case 404:
          return '没找到相关记录，可能已被删除或邀请码已失效';
        case 422:
          return '输入格式不对（手机号11位，密码至少6位）';
      }
      if (detail.isNotEmpty && detail.length < 60) return detail;
      return '服务器开小差了，请稍后重试';
    }
    if (e is StateError) return e.message;
    return '出了点问题，请稍后重试';
  }

  // ---------- 5.3 用药 ----------
  static Future<Map<String, dynamic>> addMed(
      {required String name,
      required String dosage,
      required String frequency,
      required List<String> times,
      String? startDate,
      bool mine = false}) async {
    final body = await withElder({
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'times': times,
      if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
    }, mine);
    final res = await _dio.post('/api/meds', data: body);
    return Map<String, dynamic>.from(res.data);
  }

  static Future<List> medsList({bool mine = false}) async {
    final q = await withElder({}, mine);
    final res = await _dio.get('/api/meds', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<void> updateMed(int id, Map<String, dynamic> m) async {
    await _dio.put('/api/meds/$id', data: m);
  }

  static Future<void> deleteMed(int id) async {
    await _dio.delete('/api/meds/$id');
  }

  static Future<void> deleteVital(int id) async {
    await _dio.delete('/api/vitals/$id');
  }

  static Future<void> deleteReport(int id) async {
    await _dio.delete('/api/reports/$id');
  }

  static Future<void> deleteConsult(int id) async {
    await _dio.delete('/api/consults/$id');
  }

  /// v2.0：GET /api/meds/today?elder_id&date，每项含 slots[{slot,status}]。
  static Future<List> medsToday(
      {String? date, bool mine = false, int? elderId}) async {
    final q = await withElder({if (date != null) 'date': date}, mine);
    if (elderId != null) q['elder_id'] = elderId;
    final res = await _dio.get('/api/meds/today', queryParameters: q);
    return res.data is List
        ? [
            for (final row in res.data as List)
              if (row is Map)
                {
                  ...row,
                  'name': medicationChineseName((row['name'] ?? '').toString())
                }
          ]
        : [];
  }

  static Future<Map<String, dynamic>> checkin(int medId, String slot,
      {String? date}) async {
    final window = medicationSlotWindow(slot, date: date);
    if (window != MedicationSlotWindow.due) {
      throw StateError(switch (window) {
        MedicationSlotWindow.notDue => '尚未到服药时间，请到时间后再打卡',
        MedicationSlotWindow.expired => '已超过服药时间1小时，本次打卡已关闭',
        _ => '服药时间无效，请刷新后重试',
      });
    }
    final res = await _dio.post('/api/meds/checkin', data: {
      'medication_id': medId,
      'slot': slot,
      if (date != null) 'date': date,
    });
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- 5.4 查药（JSON base64，不是 multipart） ----------
  /// 用药说明书识别只回填录药表单，不产生查药记录。
  static Future<Map<String, dynamic>> recognizeMedication(List<int> bytes,
      {bool mine = false}) async {
    final res = await _dio.post('/api/meds/recognize-instructions',
        data: {'image_base64': base64Encode(bytes)},
        queryParameters: await withElder({}, mine),
        options: Options(receiveTimeout: const Duration(minutes: 2)));
    final result = Map<String, dynamic>.from(res.data as Map);
    result['name'] = medicationChineseName((result['name'] ?? '').toString());
    return result;
  }

  static Future<Map<String, dynamic>> queryDrugByName(String name,
      {bool mine = false}) async {
    final res = await _dio.post('/api/drugs/query-name',
        data: {'name': name},
        queryParameters: await withElder({}, mine),
        options: Options(receiveTimeout: const Duration(minutes: 10)));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> queryDrugByImage(List<int> bytes,
      {String? fileName, bool mine = false}) async {
    final res = await _dio.post('/api/drugs/query',
        data: {'image_base64': base64Encode(bytes)},
        queryParameters: await withElder({}, mine),
        options: Options(receiveTimeout: const Duration(minutes: 10)));
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- 5.5 体征：type=bp/bs/hr/weight，查参 vital_type ----------
  static Future<Map<String, dynamic>> addVital(
      {required String type,
      int? systolic,
      int? diastolic,
      double? value,
      String? measuredAt,
      String? measurementContext,
      bool mine = false}) async {
    final error = validateVitalValues(type,
        systolic: systolic, diastolic: diastolic, value: value);
    if (error != null) throw StateError(error);
    final body = await withElder({
      'type': type,
      if (systolic != null) 'systolic': systolic,
      if (diastolic != null) 'diastolic': diastolic,
      if (value != null) 'value': value,
      if (measuredAt != null && measuredAt.isNotEmpty)
        'measured_at': measuredAt,
      if (type == 'bs' && measurementContext != null)
        'measurement_context': measurementContext,
    }, mine);
    final res = await _dio.post('/api/vitals', data: body);
    return Map<String, dynamic>.from(res.data);
  }

  static Future<List> vitalsList(
      {String? vitalType, int days = 30, bool mine = false}) async {
    final q = await withElder({
      if (vitalType != null) 'vital_type': vitalType,
      'days': days,
    }, mine);
    final res = await _dio.get('/api/vitals', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  /// v2.0 返回对象 {bp:[...],bs:[...]}，取当前 type 对应数组。
  static Future<List> vitalsTrend(
      {String? vitalType, int days = 30, bool mine = false}) async {
    final q = await withElder({
      if (vitalType != null) 'vital_type': vitalType,
      'days': days,
    }, mine);
    final res = await _dio.get('/api/vitals/trend', queryParameters: q);
    final d = res.data;
    if (d is List) return d;
    if (d is Map) {
      if (vitalType != null && d[vitalType] is List) return d[vitalType];
      for (final v in d.values) {
        if (v is List) return v;
      }
    }
    return [];
  }

  static String vitalsExportUrl({String? vitalType, int days = 30}) {
    final q = 'days=$days${vitalType != null ? '&vital_type=$vitalType' : ''}';
    return '${AppConfig.baseUrl}/api/vitals/export?$q';
  }

  // ---------- 5.6 问诊 ----------
  static Future<List> consultList({bool mine = false}) async {
    final q = await withElder({}, mine);
    final res = await _dio.get('/api/consults', queryParameters: q);
    final list = res.data is List ? List.from(res.data as List) : <dynamic>[];
    // 新后端在家属不传 elder_id 时会返回“本人 + 全部绑定长辈”；
    // 本人页只保留当前账号的数据，避免双端咨询记录混在一起。
    if (mine && await getRole() == 'family') {
      final userId = await getUserId();
      if (userId != null) {
        return list.where((e) {
          final m = e is Map
              ? Map<String, dynamic>.from(e)
              : const <String, dynamic>{};
          return (m['elder_id'] as num?)?.toInt() == userId;
        }).toList();
      }
    }
    return list;
  }

  static Future<Map<String, dynamic>> uploadConsult(
      List<int> bytes, String fileName,
      {int? duration,
      String? hospital,
      String? doctor,
      bool mine = false}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: fileName,
          contentType:
              DioMediaType.parse(fileName.toLowerCase().endsWith('.wav')
                  ? 'audio/wav'
                  : fileName.toLowerCase().endsWith('.mp3')
                      ? 'audio/mpeg'
                      : fileName.toLowerCase().endsWith('.aac')
                          ? 'audio/aac'
                          : 'audio/mp4')),
      if (duration != null) 'duration': duration,
      if (hospital != null) 'hospital': hospital,
      if (doctor != null) 'doctor': doctor,
      ...(await withElder({}, mine)),
    });
    final res = await _dio.post('/api/consults/upload', data: form);
    return Map<String, dynamic>.from(res.data);
  }

  /// 短录音转写只返回可编辑文字；不会提交聊天、保存体征或发送家属消息。
  static Future<String> transcribeAudio(List<int> bytes, String fileName,
      {required String purpose,
      CancelToken? cancelToken,
      String? expectedToken}) async {
    if (purpose != 'chat' && purpose != 'vitals') {
      throw ArgumentError.value(purpose, 'purpose', '必须是 chat 或 vitals');
    }
    final token = await getToken();
    if (token == null ||
        token.isEmpty ||
        (expectedToken != null && expectedToken != token)) {
      throw StateError('登录状态已变化，请重新登录后再录音。');
    }
    if (bytes.isEmpty) throw StateError('没有录到声音，请重新录音。');
    if (bytes.length > 8 * 1024 * 1024) throw StateError('录音超过8MiB，请缩短后重试。');
    final lower = fileName.toLowerCase();
    final mime = lower.endsWith('.wav')
        ? 'audio/wav'
        : lower.endsWith('.m4a')
            ? 'audio/mp4'
            : lower.endsWith('.aac')
                ? 'audio/aac'
                : lower.endsWith('.mp3')
                    ? 'audio/mpeg'
                    : 'application/octet-stream';
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: fileName, contentType: DioMediaType.parse(mime)),
      'purpose': purpose,
    });
    final res = await _dio.post('/api/speech/transcribe',
        data: form,
        cancelToken: cancelToken,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ));
    final data = res.data;
    if (await getToken() != token) throw StateError('登录状态已变化，本次转写结果已丢弃。');
    if (data is! Map) throw StateError('语音识别返回格式异常，请改用文字输入。');
    if (data['requires_confirmation'] != true) {
      throw StateError('语音结果未通过确认保护，请改用文字输入。');
    }
    if (data['transcript'] is! String ||
        (data['transcript'] as String).trim().isEmpty) {
      throw StateError('没有识别到清楚的语音，请重新录音或使用文字输入。');
    }
    return data['transcript'] as String;
  }

  static Future<Map<String, dynamic>> speechCapabilities() async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw StateError('请先登录后再使用语音转写。');
    final res = await _dio.get('/api/speech/capabilities',
        options: Options(headers: {'Authorization': 'Bearer $token'}));
    if (res.data is! Map) throw StateError('无法读取语音配置，请使用文字输入。');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// audio_url 是相对路径，前端拼 baseUrl。
  static Future<List<int>> avatarBytes(String url) async {
    final res =
        await _dio.get(url, options: Options(responseType: ResponseType.bytes));
    final d = res.data;
    if (d is List<int>) return d;
    return List<int>.from(d as List);
  }

  static String avatarFullUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl}$url';
  }

  /// 用户资料：GET /api/users/profile -> {id, nickname, gender, birth_ym, avatar_url}。
  static Future<Map<String, dynamic>> getProfile() async {
    final res = await _dio.get('/api/users/profile');
    return Map<String, dynamic>.from(res.data);
  }

  /// 更新资料：PUT /api/users/profile，全可选，只传改了的字段。
  static Future<Map<String, dynamic>> updateProfile(
      {String? nickname,
      String? gender,
      String? birthYm,
      List<int>? avatarBytes}) async {
    final res = await _dio.put('/api/users/profile', data: {
      if (nickname != null) 'nickname': nickname,
      if (gender != null) 'gender': gender,
      if (birthYm != null) 'birth_ym': birthYm,
      if (avatarBytes != null) 'avatar_base64': base64Encode(avatarBytes),
    });
    if (avatarBytes != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs
          .remove('avatar_removed_${await getRole()}_${await getUserId()}');
    }
    return Map<String, dynamic>.from(res.data);
  }

  static Future<void> deleteAvatar() async {
    await _dio.delete('/api/users/avatar');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
        'avatar_removed_${await getRole()}_${await getUserId()}', true);
    await prefs.setString('avatar', 'assets/avatars/avatar1.png');
    await prefs.remove('avatar_url');
  }

  static String consultAudioUrl(String audioUrl) {
    if (audioUrl.startsWith('http')) return audioUrl;
    return '${AppConfig.baseUrl}$audioUrl';
  }

  // ---------- 5.7 症状自查 ----------
  static Future<Map<String, dynamic>> symptomCheck(String text) async {
    final body = await withElder({'input_text': text});
    final res = await _dio.post('/api/symptom-check',
        data: body,
        options: Options(receiveTimeout: const Duration(minutes: 10)));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<List> drugRecords({bool mine = false}) async {
    final q = await withElder({}, mine);
    final res = await _dio.get('/api/drugs/records', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<List> symptomHistory({bool mine = false}) async {
    final q = await withElder({}, mine);
    final res = await _dio.get('/api/symptom-check', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<List> chatSummaries(
      {String? category, int limit = 20, bool mine = false}) async {
    final q = await withElder({
      if (category != null && category.isNotEmpty) 'category': category,
      'limit': limit,
    }, mine);
    final res = await _dio.get('/api/chat/summaries', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  // ---------- 5.8 体检报告 ----------
  static Future<List> reportList({bool mine = false}) async {
    final q = await withElder({}, mine);
    final res = await _dio.get('/api/reports', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<Map<String, dynamic>> uploadReport(
      List<int> bytes, String fileName,
      {bool mine = false}) async {
    final extension = fileName.toLowerCase().split('.').last;
    final mime = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: fileName, contentType: DioMediaType.parse(mime)),
      ...(await withElder({}, mine)),
    });
    try {
      final res = await _dio.post('/api/reports/upload',
          data: form,
          options: Options(receiveTimeout: const Duration(minutes: 10)));
      return Map<String, dynamic>.from(res.data);
    } on DioException catch (error) {
      final retake = ReportRetake.fromError(
          error, 'upload-${DateTime.now().microsecondsSinceEpoch}');
      if (retake != null) throw ReportRetakeException(retake);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createReportJob(
      List<int> bytes, String fileName,
      {bool mine = false}) async {
    final extension = fileName.toLowerCase().split('.').last;
    final mime = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: fileName, contentType: DioMediaType.parse(mime)),
      ...(await withElder({}, mine)),
    });
    final res = await _dio.post('/api/reports/jobs',
        data: form,
        options: Options(receiveTimeout: const Duration(minutes: 2)));
    if (res.statusCode != 202 || res.data is! Map) {
      throw StateError('报告任务提交失败，请稍后重试。');
    }
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> reportJobStatus(String jobId) async {
    final res =
        await _dio.get('/api/reports/jobs/${Uri.encodeComponent(jobId)}');
    if (res.data is! Map) throw StateError('报告任务状态格式异常');
    return Map<String, dynamic>.from(res.data as Map);
  }

  static String reportImageUrl(String imageUrl) {
    if (imageUrl.startsWith('http')) return imageUrl;
    return '${AppConfig.baseUrl}$imageUrl';
  }

  static Future<Uint8List> _protectedFileBytes(
      String url, String prefix) async {
    final base = Uri.parse(AppConfig.baseUrl);
    final uri = base.resolve(url);
    if (uri.origin != base.origin || !uri.path.startsWith(prefix)) {
      throw StateError('文件地址无效，请重新加载记录');
    }
    final token = await getToken();
    if (token == null) throw StateError('请先登录后再查看文件');
    final res = await _dio.get(uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(minutes: 2),
        ));
    final data = res.data;
    if (data is! List<int> || data.isEmpty) throw StateError('文件内容为空，请重新加载');
    return Uint8List.fromList(data);
  }

  static Future<Uint8List> reportImageBytes(String url) =>
      _protectedFileBytes(url, '/api/reports/image/');

  static Future<Uint8List> consultAudioBytes(String url) =>
      _protectedFileBytes(url, '/api/consults/audio/');

  static String audioMimeType(String url) {
    switch (Uri.parse(url).path.split('.').last.toLowerCase()) {
      case 'wav':
        return 'audio/wav';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case '3gp':
        return 'audio/3gpp';
      default:
        return 'audio/mp4';
    }
  }

  static Future<bool> getPrivacy() async {
    return (await privacyState())['sync_summary_to_family'] == true;
  }

  static Future<Map<String, dynamic>> privacyState() async {
    final res = await _dio.get('/api/privacy');
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> spokenVitalTurn(String text,
      {int? sessionId, bool mine = true}) async {
    final res = await _dio.post('/api/vitals/draft-conversations',
        data: await withElder({
          'text': text,
          if (sessionId != null) 'session_id': sessionId,
        }, mine));
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> getVitalDraft(int sessionId,
      {bool mine = true}) async {
    final res = await _dio.get('/api/vitals/draft-conversations/$sessionId',
        queryParameters: await withElder({}, mine));
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> confirmVitalDraft(int sessionId,
      {bool mine = true}) async {
    final res =
        await _dio.post('/api/vitals/draft-conversations/$sessionId/confirm',
            queryParameters: await withElder({}, mine),
            options: Options(headers: {
              // Retried requests for the same draft must resolve to the same confirmation.
              'Idempotency-Key': 'vital-draft-confirm-$sessionId',
            }));
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> cancelVitalDraft(int sessionId,
      {bool mine = true}) async {
    await _dio.delete('/api/vitals/draft-conversations/$sessionId',
        queryParameters: await withElder({}, mine));
  }

  static Future<Map<String, dynamic>> updateVitalDraft(
      int sessionId, Map<String, dynamic> fields,
      {bool mine = true}) async {
    final res = await _dio.patch('/api/vitals/draft-conversations/$sessionId',
        data: fields, queryParameters: await withElder({}, mine));
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<List> vitalAlerts({bool mine = true}) async {
    final res = await _dio.get('/api/vitals/alerts',
        queryParameters: await withElder({'days': 90}, mine));
    if (res.data is! List) throw StateError('提醒数据格式异常，请稍后重试');
    return res.data as List;
  }

  static Future<Map<String, dynamic>> tieredChat(String question) async {
    try {
      final res = await _dio.post('/api/chat/tiered',
          data: {'question': question},
          options: Options(receiveTimeout: const Duration(minutes: 10)));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
        return chat(question);
      }
      rethrow;
    }
  }

  static Future<bool> updatePrivacy(bool value) async {
    final res =
        await _dio.put('/api/privacy', data: {'sync_summary_to_family': value});
    return res.data['sync_summary_to_family'] == true;
  }

  /// 体征 PDF 导出：后端 GET /api/vitals/export，返回 PDF 二进制。
  static Future<List<int>> vitalsExportPdf(
      {String? vitalType, int days = 30, bool mine = false}) async {
    final q = await withElder({
      if (vitalType != null) 'vital_type': vitalType,
      'days': days,
    }, mine);
    final res = await _dio.get('/api/vitals/export',
        queryParameters: q,
        options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(minutes: 2)));
    final data = res.data;
    if (data is List<int>) return data;
    return [];
  }

  // ---------- 5.9 天气 ----------
  static Future<Map<String, dynamic>> weatherRemind(
      {String? city, double? lat, double? lon}) async {
    final res = await _dio.get('/api/weather/remind', queryParameters: {
      if (city != null) 'city': city,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
    });
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- 5.10 问答：请求 {question}，响应 {answer,module,steps} ----------
  static Future<Map<String, dynamic>> chat(String question) async {
    final res = await _dio.post('/api/chat',
        data: {'question': question},
        options: Options(receiveTimeout: const Duration(minutes: 10)));
    if (res.data is Map) return Map<String, dynamic>.from(res.data);
    return {'answer': res.data.toString()};
  }
}
