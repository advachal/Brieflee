import 'package:brieflee/core/intelligence/judgment_deduplicator.dart';
import 'package:brieflee/core/mock/demo_dataset.dart';
import 'package:brieflee/core/models/models.dart';
import 'package:brieflee/shared/utilities/mock_latency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => MockLatency.base = Duration.zero);

  test('a judgment found in several repositories counts once and keeps every source', () {
    final base = DemoDataset.instance.judgments.firstWhere(
      (j) => j.sources.length >= 2,
    );
    final raw = [
      for (final s in base.sources)
        RawJudgmentRecord(
          source: s.type,
          judgment: Judgment.fromJson({
            ...base.toJson(),
            'sources': [s.toJson()],
          }),
        ),
    ];
    final merged = const JudgmentDeduplicator().merge(raw);
    expect(merged, hasLength(1));
    expect(
      merged.single.sources.map((s) => s.type).toSet(),
      base.sources.map((s) => s.type).toSet(),
    );
  });

  test('conflicting citations are flagged and the official record wins', () {
    final base = DemoDataset.instance.judgments.first;
    final official = Judgment.fromJson({
      ...base.toJson(),
      'citation': 'OFFICIAL-1',
      'sources': [
        JudgmentSourceRef(
          type: SourceType.official,
          retrievedAt: DateTime(2026),
          documentVersion: 'v1',
          verification: VerificationStatus.verified,
        ).toJson(),
      ],
    });
    final repo = Judgment.fromJson({
      ...base.toJson(),
      'citation': 'REPO-1',
      'sources': [
        JudgmentSourceRef(
          type: SourceType.indianKanoon,
          retrievedAt: DateTime(2026),
          documentVersion: 'v1',
          verification: VerificationStatus.unverified,
        ).toJson(),
      ],
    });
    final merged = const JudgmentDeduplicator().merge([
      RawJudgmentRecord(source: SourceType.indianKanoon, judgment: repo),
      RawJudgmentRecord(source: SourceType.official, judgment: official),
    ]);
    expect(merged.single.citation, 'OFFICIAL-1');
    expect(merged.single.hasConflict, isTrue);
  });

  test('judgment JSON round-trips', () {
    final j = DemoDataset.instance.judgments.first;
    expect(Judgment.fromJson(j.toJson()).toJson(), j.toJson());
  });

  test('demo dataset is deterministic, fictional and well-formed', () {
    final d = DemoDataset.instance;
    final ids = d.judgments.map((j) => j.id).toSet();
    expect(ids.length, d.judgments.length);
    for (final j in d.judgments) {
      expect(j.citation, startsWith('DEMO-'));
      expect(j.title, contains('(Demo)'));
      expect(j.sources, isNotEmpty);
    }
  });
}
