import '../../../core/errors/app_failure.dart';
import '../../../core/intelligence/judgment_deduplicator.dart';
import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../domain/judgment_repository.dart';

/// Simulates the retrieval pipeline: each demo judgment is split into one raw
/// record per repository, then merged back by [JudgmentDeduplicator] so a
/// case found in several repositories is counted once.
class MockJudgmentRepository implements JudgmentRepository {
  MockJudgmentRepository(DemoDataset data) {
    final raw = <RawJudgmentRecord>[];
    for (final j in data.judgments) {
      for (final s in j.sources) {
        raw.add(
          RawJudgmentRecord(source: s.type, judgment: _withSingleSource(j, s)),
        );
      }
    }
    _raw = raw.length;
    final merged = const JudgmentDeduplicator().merge(raw)
      ..sort((a, b) => b.date.compareTo(a.date));
    _byId = {for (final j in merged) j.id: j};
  }

  late final int _raw;
  late final Map<String, Judgment> _byId;

  List<Judgment> get index => _byId.values.toList();

  static Judgment _withSingleSource(Judgment j, JudgmentSourceRef s) =>
      Judgment(
        id: j.id,
        title: j.title,
        citation: j.citation,
        caseNumber: j.caseNumber,
        courtId: j.courtId,
        benchJudgeIds: j.benchJudgeIds,
        date: j.date,
        category: j.category,
        statutes: j.statutes,
        stage: j.stage,
        disposition: j.disposition,
        dispositionConfidence: j.dispositionConfidence,
        reviewStatus: j.reviewStatus,
        appearances: j.appearances,
        sources: [s],
        passages: j.passages,
        summary: j.summary,
        conflictNote: j.conflictNote,
      );

  @override
  Future<Judgment> get(String id) async {
    await MockLatency.wait(0.5);
    final j = _byId[id];
    if (j == null) throw const NotFoundFailure('This judgment');
    return j;
  }

  @override
  Future<List<Judgment>> getMany(List<String> ids) async {
    await MockLatency.wait(0.4);
    return [
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!,
    ];
  }

  @override
  Future<List<Judgment>> all() async {
    await MockLatency.wait(0.4);
    return index;
  }

  @override
  ({int rawRecords, int uniqueCases}) indexStats() =>
      (rawRecords: _raw, uniqueCases: _byId.length);
}
