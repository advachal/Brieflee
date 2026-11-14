import '../../../core/models/models.dart';

/// Unified, deduplicated judgment index. GET /v1/judgments/{id}.
abstract interface class JudgmentRepository {
  Future<Judgment> get(String id);
  Future<List<Judgment>> getMany(List<String> ids);

  /// All judgments in the index (demo only; production pages and filters
  /// server-side).
  Future<List<Judgment>> all();

  /// Raw source references seen before deduplication, and unique cases after.
  ({int rawRecords, int uniqueCases}) indexStats();
}
