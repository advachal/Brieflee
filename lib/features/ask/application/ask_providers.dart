import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/public_records/ask_engine.dart';
import '../../../core/public_records/directory.dart';
import '../../../core/public_records/public_records.dart';
import '../data/bundled_public_records_repository.dart';
import '../data/knowledge_service_client.dart';
import '../domain/public_records_repository.dart';

final publicRecordsRepositoryProvider = Provider<PublicRecordsRepository>(
  (ref) => BundledPublicRecordsRepository(),
);

/// Loaded once and kept for the session.
final publicRecordsProvider = FutureProvider<PublicRecordsSnapshot>(
  (ref) => ref.watch(publicRecordsRepositoryProvider).load(),
);

final askEngineProvider = FutureProvider<AskEngine>((ref) async {
  final snapshot = await ref.watch(publicRecordsProvider.future);
  return AskEngine(snapshot);
});

final knowledgeServiceProvider = Provider<KnowledgeServiceClient>(
  (ref) => KnowledgeServiceClient(),
);

/// Answers one question in real time against the knowledge layer.
final askAnswerProvider = FutureProvider.family<AskAnswer?, String>((
  ref,
  question,
) async {
  final q = question.trim();
  if (q.isEmpty) return null;
  final engine = await ref.watch(askEngineProvider.future);
  return engine.ask(q);
});

/// Optional grounded narrative from the knowledge service.
final generatedAnswerProvider = FutureProvider.family<String?, String>((
  ref,
  question,
) async {
  final client = ref.watch(knowledgeServiceProvider);
  if (!client.configured || question.trim().isEmpty) return null;
  try {
    return await client.generatedAnswer(question.trim());
  } catch (_) {
    return null;
  }
});

/// Real counsel and judge directory, built once from the records.
final directoryProvider = FutureProvider<RecordsDirectory>((ref) async {
  final snapshot = await ref.watch(publicRecordsProvider.future);
  return RecordsDirectory(snapshot);
});

/// AI analysis of an uploaded document by the knowledge service, if
/// connected. The key is the JSON request body (text, side, confirmed facts).
final documentAnalysisProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, request) async {
      final client = ref.watch(knowledgeServiceProvider);
      if (!client.configured) return null;
      try {
        return await client.analyzeDocument(request);
      } catch (_) {
        return null;
      }
    });

/// Case facts read from an uploaded document by the AI, if connected.
final documentFactsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, text) async {
      final client = ref.watch(knowledgeServiceProvider);
      if (!client.configured) return null;
      try {
        return await client.extractFacts(text);
      } catch (_) {
        return null;
      }
    });
