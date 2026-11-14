import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/demo_providers.dart';
import '../../../core/models/models.dart';
import '../../judgment_viewer/application/judgment_providers.dart';
import '../data/mock_recommendation_repository.dart';
import '../domain/recommendation_repository.dart';

final recommendationRepositoryProvider = Provider<RecommendationRepository>(
  (ref) => MockRecommendationRepository(
    ref.watch(demoDatasetProvider),
    ref.watch(judgmentRepositoryProvider),
  ),
);

/// Scoring weights, adjustable from the admin dashboard. Each change bumps
/// the methodology version.
class ScoringWeightsController extends Notifier<ScoringWeights> {
  @override
  ScoringWeights build() => const ScoringWeights();

  void update(ScoringWeights w) => state = w;
  void reset() => state = ScoringWeights(revision: state.revision + 1);
}

final scoringWeightsProvider =
    NotifierProvider<ScoringWeightsController, ScoringWeights>(
      ScoringWeightsController.new,
    );

/// Filters for one recommendation run.
class ResultFilters extends Notifier<SearchFilters> {
  ResultFilters(this.recommendationId);
  final String recommendationId;

  @override
  SearchFilters build() {
    return ref
            .read(recommendationRepositoryProvider)
            .initialFilters(recommendationId) ??
        const SearchFilters();
  }

  void set(SearchFilters f) => state = f;
}

final resultFiltersProvider =
    NotifierProvider.family<ResultFilters, SearchFilters, String>(
      ResultFilters.new,
    );

final recommendationProvider = FutureProvider.family<Recommendation, String>((
  ref,
  id,
) {
  final filters = ref.watch(resultFiltersProvider(id));
  final weights = ref.watch(scoringWeightsProvider);
  return ref
      .watch(recommendationRepositoryProvider)
      .get(id, filters: filters, weights: weights);
});

/// The advocate whose evidence is open in the right-hand panel.
class SelectedAdvocate extends Notifier<String?> {
  SelectedAdvocate(this.recommendationId);
  final String recommendationId;

  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedAdvocateProvider =
    NotifierProvider.family<SelectedAdvocate, String?, String>(
      SelectedAdvocate.new,
    );
