import '../../../core/api/brieflee_api.dart';
import '../../../core/models/models.dart';

/// Matters, their private documents and analysis.
/// Backed by `/v1/matters*` in production.
abstract interface class MatterRepository {
  Future<List<Matter>> list();
  Future<Matter> get(String id);
  Future<Matter> create(CreateMatterRequest request);
  Future<MatterDocument> addDocument(
    String matterId, {
    required String fileName,
    required int sizeBytes,
    required DocumentKind kind,
  });
  Future<Matter> removeDocument(String matterId, String documentId);

  /// POST /v1/matters/{id}/analyze, then poll the job until it completes.
  Stream<Job> analyze(String matterId);
  Future<Matter> saveAnalysis(String matterId, CaseAnalysis analysis);
  Future<Matter> attachRecommendation(String matterId, String recommendationId);
  Future<Matter> updateShortlist(String matterId, List<String> advocateIds);
  Future<Matter> setMonitored(String matterId, bool monitored);

  /// DELETE /v1/matters/{id}: removes the matter and its private documents.
  Future<void> delete(String matterId);
  Future<void> deleteAll();
}
