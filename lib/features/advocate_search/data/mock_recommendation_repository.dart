import '../../../core/api/brieflee_api.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/intelligence/scoring_engine.dart';
import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../../judgment_viewer/domain/judgment_repository.dart';
import '../domain/recommendation_repository.dart';

class _Stored {
  _Stored(this.matterId, this.ctx, this.filters, this.createdAt);
  final String matterId;
  final MatchContext ctx;
  final SearchFilters filters;
  final DateTime createdAt;
}

/// Runs the real [ScoringEngine] over the illustrative demo index.
class MockRecommendationRepository implements RecommendationRepository {
  MockRecommendationRepository(this._data, this._judgments) {
    // A ready-made recommendation for the seeded demo matter.
    _store['rec-demo-1'] = _Stored(
      'm-demo-1',
      const MatchContext(
        courtId: 'dhc',
        category: DemoCategories.trademark,
        stage: CaseStage.interimInjunction,
        statutes: ['Trade Marks Act, 1999 s.29', 'Trade Marks Act, 1999 s.135'],
        benchJudgeIds: ['j1'],
      ),
      const SearchFilters(courtId: 'dhc'),
      DateTime(2026, 11, 10, 11, 45),
    );
  }

  final DemoDataset _data;
  final JudgmentRepository _judgments;
  final Map<String, _Stored> _store = {};
  int _seq = 1;

  List<SourceRun> _sourceRuns() {
    final stats = _judgments.indexStats();
    return [
      SourceRun(
        source: SourceType.vakilaj,
        status: AppConfig.vakilajEnabled
            ? SourceRunStatus.ok
            : SourceRunStatus.disabled,
        message:
            'Primary repository. Not queried: access method and reuse '
            'permissions are still being confirmed.',
      ),
      SourceRun(
        source: SourceType.indianKanoon,
        status: AppConfig.indianKanoonEnabled
            ? SourceRunStatus.ok
            : SourceRunStatus.disabled,
        message: 'Secondary repository. Not queried: permission pending.',
      ),
      SourceRun(
        source: SourceType.official,
        status: AppConfig.officialCourtSourcesEnabled
            ? SourceRunStatus.ok
            : SourceRunStatus.disabled,
        message: 'Authoritative verification. Not connected in this prototype.',
      ),
      SourceRun(
        source: SourceType.userUpload,
        status: SourceRunStatus.ok,
        message:
            'Illustrative demo index: ${stats.rawRecords} source references '
            'deduplicated into ${stats.uniqueCases} fictional cases.',
        records: stats.uniqueCases,
      ),
    ];
  }

  @override
  Stream<Job> start(
    StartRecommendationRequest r, {
    required List<String> benchJudgeIds,
  }) async* {
    final id = 'rec-${_seq++}';
    final jobId = 'job-$id';
    final steps = <String>[
      'Vakilaj adapter: skipped (not connected)',
      'Indian Kanoon adapter: skipped (not connected)',
      'Official verification: skipped (not connected)',
      'Searching illustrative demo index',
      'Resolving advocate identities and roles',
      'Classifying outcomes and building evidence',
      'Scoring with ${r.methodologyVersion}',
    ];
    for (var i = 0; i < steps.length; i++) {
      yield Job(
        id: jobId,
        status: JobStatus.running,
        progress: i / steps.length,
        step: steps[i],
      );
      await MockLatency.wait(0.9);
    }
    final a = r.analysis;
    _store[id] = _Stored(
      r.matterId,
      MatchContext(
        courtId: a.courtId,
        category: a.caseCategory,
        stage: a.stage,
        statutes: a.statutes,
        benchJudgeIds: benchJudgeIds,
      ),
      r.filters,
      DateTime.now(),
    );
    yield Job(
      id: jobId,
      status: JobStatus.succeeded,
      progress: 1,
      step: 'Recommendations ready',
      resultId: id,
    );
  }

  @override
  Future<Recommendation> get(
    String id, {
    SearchFilters? filters,
    ScoringWeights? weights,
  }) async {
    await MockLatency.wait(0.6);
    final s = _store[id];
    if (s == null) throw const NotFoundFailure('This recommendation');
    final engine = ScoringEngine(
      weights: weights ?? const ScoringWeights(),
      fixedAsOf: DemoDataset.referenceDate,
    );
    final rec = engine.recommend(
      id: id,
      matterId: s.matterId,
      ctx: s.ctx,
      filters: filters ?? s.filters,
      advocates: _data.advocates,
      judgments: await _judgments.all(),
      mentionOnlyCounts: _data.mentionOnlyCounts,
      sourceRuns: _sourceRuns(),
    );
    return Recommendation(
      id: rec.id,
      matterId: rec.matterId,
      createdAt: s.createdAt,
      methodologyVersion: rec.methodologyVersion,
      filters: rec.filters,
      ranked: rec.ranked,
      insufficient: rec.insufficient,
      sourceRuns: rec.sourceRuns,
      benchJudgeIds: rec.benchJudgeIds,
    );
  }

  @override
  MatchContext? contextFor(String id) => _store[id]?.ctx;

  @override
  SearchFilters? initialFilters(String id) => _store[id]?.filters;
}
