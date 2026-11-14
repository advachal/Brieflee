import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';

/// Optional client for the full-text RAG service in server/ (POST /v1/ask).
///
/// The app answers questions on its own from the bundled knowledge layer.
/// When a service URL is configured, it also asks the service, which
/// searches the full judgment text and can add a grounded, cited narrative.
class KnowledgeServiceClient {
  KnowledgeServiceClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _base = baseUrl ?? AppConfig.knowledgeServiceUrl;

  final http.Client _client;
  final String _base;

  bool get configured => _base.isNotEmpty;

  /// Returns the service's generated answer, or null if none is available.
  Future<String?> generatedAnswer(String question) async {
    if (!configured) return null;
    final res = await _client
        .post(
          Uri.parse('$_base/v1/ask'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'question': question, 'limit': 12}),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['answer'] as String?;
  }
}
