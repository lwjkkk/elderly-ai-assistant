import 'package:dio/dio.dart';

/// A server-requested retake, never inferred from a generic upload failure.
class ReportRetake {
  final String id;
  final String message;
  final List<String> requirements;

  const ReportRetake(this.id, this.message, this.requirements);

  static const shootingRequirements = [
    '一次拍摄一页，保留完整表头、结果、单位和参考条件；原件没有的字段无需补造。',
    '报告摆正铺平，镜头正对纸面。',
    '光线均匀，避开反光和遮挡，对焦小字。',
    '上传清晰原图，避免压缩或截断。',
  ];

  static ReportRetake? fromPayload(dynamic raw, String id) {
    if (raw is! Map) return null;
    final details =
        raw['ocr_details'] is Map ? raw['ocr_details'] as Map : const {};
    final retake = raw['retake'] is Map
        ? raw['retake'] as Map
        : details['retake'] is Map
            ? details['retake'] as Map
            : const {};
    if (raw['retake_required'] != true &&
        details['retake_required'] != true &&
        raw['code'] != 'report_retake_required' &&
        retake['required'] != true) {
      return null;
    }
    final message = (retake['message'] ??
            raw['detail'] ??
            raw['error'] ??
            '本次未能可靠识别报告，请重新拍摄清晰、完整的报告图片。')
        .toString();
    final requirements = retake['requirements'] is List
        ? (retake['requirements'] as List)
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList()
        : <String>[];
    return ReportRetake(
        id, message, {...requirements, ...shootingRequirements}.toList());
  }

  static ReportRetake? fromError(Object error, String id) {
    if (error is ReportRetakeException) return error.retake;
    if (error is! DioException || error.response?.statusCode != 422) {
      return null;
    }
    return fromPayload(error.response?.data, id);
  }
}

class ReportRetakeException implements Exception {
  final ReportRetake retake;
  const ReportRetakeException(this.retake);
  @override
  String toString() => retake.message;
}
