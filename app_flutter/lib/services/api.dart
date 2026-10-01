import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('token');
  }

  static Future<String?> getRole() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('role');
  }

  static Future<void> saveAuth(String token, String role) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token);
    await p.setString('role', role);
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  static Future<void> clearAuth() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
  }

  /// A 后端 Day1 接口：POST /api/auth/register {phone,password,role,nickname}
  static Future<void> register(
      {required String phone,
      required String password,
      required String role,
      String nickname = ''}) async {
    await _dio.post('/api/auth/register', data: {
      'phone': phone,
      'password': password,
      'role': role,
      'nickname': nickname,
    });
  }

  /// POST /api/auth/login -> {token}
  static Future<void> login(
      {required String phone,
      required String password,
      required String role}) async {
    final res = await _dio.post('/api/auth/login', data: {
      'phone': phone,
      'password': password,
    });
    final token = res.data['token'] ?? res.data['access_token'] ?? '';
    await saveAuth(token.toString(), role);
  }

  /// POST /api/bind/invite -> {invite_code}
  static Future<String> createInvite() async {
    final res = await _dio.post('/api/bind/invite');
    return res.data['invite_code'].toString();
  }

  /// POST /api/bind/accept {invite_code}
  static Future<void> acceptInvite(String code) async {
    await _dio.post('/api/bind/accept', data: {'invite_code': code});
  }

  /// GET /api/bind/list
  static Future<List> bindList() async {
    final res = await _dio.get('/api/bind/list');
    if (res.data is List) return res.data;
    return res.data['data'] ?? [];
  }
}
