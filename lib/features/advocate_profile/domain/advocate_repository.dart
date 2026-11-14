import '../../../core/models/models.dart';

/// GET /v1/advocates/{id} and GET /v1/advocates/{id}/cases.
abstract interface class AdvocateRepository {
  Future<List<Advocate>> all();
  Future<Advocate> get(String id);

  /// Every judgment in which the advocate appears, any verification state.
  Future<List<Judgment>> cases(String id);

  /// Search mentions that could not be linked to a verified appearance.
  int mentionOnlyCount(String id);
}
