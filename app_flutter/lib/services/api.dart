import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

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
  static const disclaimer =
      '本内容仅供健康科普参考，不构成医疗诊断或用药建议。具体诊疗请遵医嘱，如有急症请立即拨打120。';

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
    await p.clear();
    _dio.options.headers.remove('Authorization');
  }

  /// 家属必填 elder_id 的统一拼参。
  /// 家属必填 elder_id 的统一拼参。
  /// 本地没存过（老版本绑定过、重装过）就现场从绑定列表里补一次。
  static Future<Map<String, dynamic>> withElder(
      [Map<String, dynamic>? extra, bool mine = false]) async {
    final m = Map<String, dynamic>.from(extra ?? {});
    final role = await getRole();
    if (role == 'family' && !mine) {
      var eid = await getElderId();
      if (eid == null) {
        try {
          final binds = await bindList();
          for (final b in binds) {
            final bm = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
            if (bm['status'] == 'active' && bm['elder_id'] is int) {
              eid = bm['elder_id'] as int;
              await setElderId(eid);
              break;
            }
          }
        } catch (_) {}
      }
      if (eid != null) m['elder_id'] = eid;
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
    await saveAuth((d['access_token'] ?? '').toString(),
        (d['role'] ?? 'elder').toString(),
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
    final res = await _dio.post('/api/auth/login_by_code',
        data: {'phone': phone, 'code': code});
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


  /// 把报错翻译成长辈能看懂的话，各页面直接用。
  static String friendly(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      dynamic data = e.response?.data;
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
    return '出了点问题，请稍后重试';
  }

  // ---------- 5.3 用药 ----------
  static Future<Map<String, dynamic>> addMed(
      {required String name,
      required String dosage,
      required String frequency,
      required List<String> times}) async {
    final body = await withElder({
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'times': times,
    });
    final res = await _dio.post('/api/meds', data: body);
    return Map<String, dynamic>.from(res.data);
  }

  static Future<List> medsList() async {
    final q = await withElder();
    final res = await _dio.get('/api/meds', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<void> updateMed(int id, Map<String, dynamic> m) async {
    await _dio.put('/api/meds/$id', data: m);
  }

  static Future<void> deleteMed(int id) async {
    await _dio.delete('/api/meds/$id');
  }

  /// v2.0：GET /api/meds/today?elder_id&date，每项含 slots[{slot,status}]。
  static Future<List> medsToday({String? date, bool mine = false}) async {
    final q = await withElder({if (date != null) 'date': date}, mine);
    final res = await _dio.get('/api/meds/today', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<Map<String, dynamic>> checkin(int medId, String slot,
      {String? date}) async {
    final res = await _dio.post('/api/meds/checkin', data: {
      'medication_id': medId,
      'slot': slot,
      if (date != null) 'date': date,
    });
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- 5.4 查药（JSON base64，不是 multipart） ----------
  static Future<Map<String, dynamic>> queryDrugByName(String name) async {
    final res = await _dio.post('/api/drugs/query-name', data: {'name': name});
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> queryDrugByImage(
      List<int> bytes, [String? fileName]) async {
    final res = await _dio.post('/api/drugs/query',
        data: {'image_base64': base64Encode(bytes)});
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- 5.5 体征：type=bp/bs/hr/weight，查参 vital_type ----------
  static Future<Map<String, dynamic>> addVital(
      {required String type,
      int? systolic,
      int? diastolic,
      double? value, bool mine = false}) async {
    final body = await withElder({
      'type': type,
      if (systolic != null) 'systolic': systolic,
      if (diastolic != null) 'diastolic': diastolic,
      if (value != null) 'value': value,
    }, mine);
    final res = await _dio.post('/api/vitals', data: body);
    return Map<String, dynamic>.from(res.data);
  }

  static Future<List> vitalsList(
      {String? vitalType, int days = 30}) async {
    final q = await withElder({
      if (vitalType != null) 'vital_type': vitalType,
      'days': days,
    });
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
    return res.data is List ? res.data : [];
  }

  static Future<Map<String, dynamic>> uploadConsult(List<int> bytes, String fileName,
      {int? duration, String? hospital, String? doctor}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      if (duration != null) 'duration': duration,
      if (hospital != null) 'hospital': hospital,
      if (doctor != null) 'doctor': doctor,
      ...(await withElder()),
    });
    final res = await _dio.post('/api/consults/upload', data: form);
    return Map<String, dynamic>.from(res.data);
  }

  /// audio_url 是相对路径，前端拼 baseUrl。
  static String consultAudioUrl(String audioUrl) {
    if (audioUrl.startsWith('http')) return audioUrl;
    return '${AppConfig.baseUrl}$audioUrl';
  }

  // ---------- 5.7 症状自查 ----------
  static Future<Map<String, dynamic>> symptomCheck(String text) async {
    final body = await withElder({'input_text': text});
    final res = await _dio.post('/api/symptom-check', data: body);
    return Map<String, dynamic>.from(res.data);
  }

  static Future<List> symptomHistory() async {
    final q = await withElder();
    final res = await _dio.get('/api/symptom-check', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  // ---------- 5.8 体检报告 ----------
  static Future<List> reportList({bool mine = false}) async {
    final q = await withElder({}, mine);
    final res = await _dio.get('/api/reports', queryParameters: q);
    return res.data is List ? res.data : [];
  }

  static Future<Map<String, dynamic>> uploadReport(List<int> bytes, String fileName, {bool mine = false}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      ...(await withElder({}, mine)),
    });
    final res = await _dio.post('/api/reports/upload', data: form);
    return Map<String, dynamic>.from(res.data);
  }

  static String reportImageUrl(String imageUrl) {
    if (imageUrl.startsWith('http')) return imageUrl;
    return '${AppConfig.baseUrl}$imageUrl';
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
    final res = await _dio.post('/api/chat', data: {'question': question});
    if (res.data is Map) return Map<String, dynamic>.from(res.data);
    return {'answer': res.data.toString()};
  }
}
