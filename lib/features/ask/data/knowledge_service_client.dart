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
      _base = baseUrl ?? AppConfig.resolvedKnowledgeServiceUrl;

  final http.Client _client;
  final String _base;

  bool get configured => _base.isNotEmpty;

  /// The service's answer over its full-text database: similar decisions,
  /// counsel evidence and (with an AI key) a grounded summary.
  Future<Map<String, dynamic>?> ask(String question) =>
      _post('/v1/ask', jsonEncode({'question': question, 'limit': 12}));

  /// Sends an uploaded document's text for analysis: the service chunks it,
  /// finds its legal issues with Claude and links each issue to similar
  /// decisions in the knowledge layer. Returns null when unavailable.
  ///
  /// [request] is the JSON body: {"text", optional "side" and "facts"}.
  Future<Map<String, dynamic>?> analyzeDocument(String request) =>
      _post('/v1/analyze', request);

  /// Structured case facts read from the document by the AI (court, parties,
  /// deciding judges, statutes, counsel, issues, stage). Null if unavailable.
  Future<Map<String, dynamic>?> extractFacts(String text) =>
      _post('/v1/extract', jsonEncode({'text': text}));

  Future<Map<String, dynamic>?> _post(String path, String body) async {
    if (!configured) return null;
    final res = await _client
        .post(
          Uri.parse('$_base$path'),
          headers: {'content-type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 150));
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
