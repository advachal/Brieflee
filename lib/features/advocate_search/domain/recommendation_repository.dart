import '../../../core/api/brieflee_api.dart';
import '../../../core/intelligence/scoring_engine.dart';
import '../../../core/models/models.dart';

/// POST /v1/recommendations (returns a job) and GET /v1/recommendations/{id}.
abstract interface class RecommendationRepository {
  /// Starts matching. Emits job progress; the final job carries `resultId`.
  Stream<Job> start(
    StartRecommendationRequest request, {
    required List<String> benchJudgeIds,
  });

  /// Returns the recommendation, re-scored with [filters] and [weights] when
  /// given. Filters run against the same evidence set.
  Future<Recommendation> get(
    String id, {
    SearchFilters? filters,
    ScoringWeights? weights,
  });

  MatchContext? contextFor(String id);

  /// Filters the run was started with.
  SearchFilters? initialFilters(String id);
}
