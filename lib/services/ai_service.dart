import 'dart:convert';

import 'package:http/http.dart' as http;

/// 对接本地 Ollama / 任意 OpenAI 兼容接口
class AiService {
  AiService({required this.baseUrl, required this.model});

  String baseUrl;
  String model;

  /// Ollama: POST /api/chat
  /// OpenAI 兼容: POST /v1/chat/completions
  Future<String> chat({
    required String system,
    required String user,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    // 优先尝试 OpenAI 兼容
    try {
      final r = await http
          .post(
            Uri.parse('$base/v1/chat/completions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
              'temperature': 0.3,
            }),
          )
          .timeout(const Duration(seconds: 120));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final choices = j['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          return (choices[0]['message']['content'] as String?)?.trim() ?? '';
        }
      }
    } catch (_) {}

    // Ollama native
    final r = await http
        .post(
          Uri.parse('$base/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 120));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('AI 请求失败 (${r.statusCode}): ${r.body}');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final msg = j['message'] as Map<String, dynamic>?;
    return (msg?['content'] as String?)?.trim() ?? '';
  }
}
