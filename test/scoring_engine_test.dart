import 'package:brieflee/core/intelligence/scoring_engine.dart';
import 'package:brieflee/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _asOf = DateTime(2026, 11, 1);

Judgment _j(
  String id, {
  required String adv,
  RepresentationSide side = RepresentationSide.plaintiff,
  CaseDisposition d = CaseDisposition.interimGranted,
  String category = 'Trademark infringement',
  CaseStage stage = CaseStage.interimInjunction,
  List<String> bench = const ['j1'],
  VerificationStatus v = VerificationStatus.verified,
  int yearsAgo = 1,
}) => Judgment(
  id: id,
  title: 'Test $id',
  citation: 'TEST-$id',
  caseNumber: 'CS $id',
  courtId: 'dhc',
  benchJudgeIds: bench,
  date: DateTime(_asOf.year - yearsAgo, 6, 1),
  category: category,
  statutes: const ['s.29'],
  stage: stage,
  disposition: d,
  dispositionConfidence: 0.9,
  reviewStatus: ReviewStatus.autoAccepted,
  appearances: [
    Appearance(
      advocateId: adv,
      side: side,
      role: CounselRole.arguing,
      verification: v,
      confidence: 0.9,
    ),
  ],
  sources: const [],
  passages: const [],
  summary: '',
);

const _adv = Advocate(
  id: 'x',
  displayName: 'Advocate X',
  aliases: [],
  chamber: '',
  practiceSince: 2000,
  practiceAreas: [],
  identityVerification: VerificationStatus.verified,
);

const _ctx = MatchContext(
  courtId: 'dhc',
  category: 'Trademark infringement',
  stage: CaseStage.interimInjunction,
  statutes: ['s.29'],
  benchJudgeIds: ['j1'],
);

void main() {
  final engine = ScoringEngine(fixedAsOf: _asOf);

  group('CaseDisposition', () {
    test('flips favorable/unfavorable for the responding side', () {
      expect(
        CaseDisposition.interimGranted.outcomeFor(RepresentationSide.plaintiff),
        PartyOutcome.favorable,
      );
      expect(
        CaseDisposition.interimGranted.outcomeFor(RepresentationSide.defendant),
        PartyOutcome.unfavorable,
      );
      expect(
        CaseDisposition.partlyAllowed.outcomeFor(RepresentationSide.respondent),
        PartyOutcome.mixed,
      );
    });

    test(
      'settled, withdrawn, procedural and indeterminate are not eligible',
      () {
        for (final d in [
          CaseDisposition.settled,
          CaseDisposition.withdrawn,
          CaseDisposition.procedural,
          CaseDisposition.indeterminate,
        ]) {
          expect(d.eligible, isFalse);
          expect(
            d.outcomeFor(RepresentationSide.plaintiff),
            PartyOutcome.excluded,
          );
        }
      },
    );
  });

  group('ScoringEngine', () {
    test(
      'ineligible dispositions are excluded from the outcome denominator',
      () {
        final js = [
          for (var i = 0; i < 5; i++) _j('w$i', adv: 'x'),
          for (var i = 0; i < 3; i++)
            _j('s$i', adv: 'x', d: CaseDisposition.settled),
          _j('u0', adv: 'x', v: VerificationStatus.unverified),
        ];
        final item = engine.scoreAdvocate(
          advocate: _adv,
          ctx: _ctx,
          filters: const SearchFilters(),
          judgments: js,
          benchJudgeIds: const ['j1'],
        )!;
        expect(item.metrics.comparableIds.length, 9);
        expect(item.metrics.eligibleIds.length, 5);
        expect(item.metrics.favorableIds.length, 5);
        expect(item.metrics.excludedIds.length, 4);
        expect(item.metrics.favorableRate, 1.0);
      },
    );

    test('8/10 does not automatically outrank 70/100 on outcome evidence', () {
      List<Judgment> make(String p, int fav, int total) => [
        for (var i = 0; i < total; i++)
          _j(
            '$p$i',
            adv: 'x',
            d: i < fav
                ? CaseDisposition.interimGranted
                : CaseDisposition.interimRefused,
          ),
      ];
      final small = engine.scoreAdvocate(
        advocate: _adv,
        ctx: _ctx,
        filters: const SearchFilters(),
        judgments: make('a', 8, 10),
        benchJudgeIds: const [],
      )!;
      final large = engine.scoreAdvocate(
        advocate: _adv,
        ctx: _ctx,
        filters: const SearchFilters(),
        judgments: make('b', 70, 100),
        benchJudgeIds: const [],
      )!;
      expect(
        small.metrics.favorableRate! > large.metrics.favorableRate!,
        isTrue,
      );
      expect(large.components.outcome, greaterThan(small.components.outcome));
    });

    test(
      'too little verified evidence is reported as insufficient, not ranked',
      () {
        final js = [_j('a', adv: 'x'), _j('b', adv: 'x')];
        final item = engine.scoreAdvocate(
          advocate: _adv,
          ctx: _ctx,
          filters: const SearchFilters(),
          judgments: js,
          benchJudgeIds: const ['j1'],
        )!;
        expect(item.insufficient, isTrue);
        expect(item.reliability, EvidenceReliability.insufficient);
      },
    );

    test('no comparable matters returns null', () {
      final js = [_j('a', adv: 'x', category: 'Patent')];
      expect(
        engine.scoreAdvocate(
          advocate: _adv,
          ctx: _ctx,
          filters: const SearchFilters(),
          judgments: js,
          benchJudgeIds: const [],
        ),
        isNull,
      );
    });

    test('judge weight is redistributed when no bench is identified', () {
      final js = [
        for (var i = 0; i < 6; i++) _j('a$i', adv: 'x', bench: const ['j9']),
      ];
      final withBench = engine.scoreAdvocate(
        advocate: _adv,
        ctx: _ctx,
        filters: const SearchFilters(),
        judgments: js,
        benchJudgeIds: const ['j1'],
      )!;
      final noBench = engine.scoreAdvocate(
        advocate: _adv,
        ctx: _ctx,
        filters: const SearchFilters(),
        judgments: js,
        benchJudgeIds: const [],
      )!;
      expect(withBench.components.judgeApplied, isTrue);
      expect(noBench.components.judgeApplied, isFalse);
      // No matters before j1, so dropping the judge component raises the score.
      expect(noBench.score, greaterThan(withBench.score));
    });

    test('side filter limits the pool', () {
      final js = [
        for (var i = 0; i < 5; i++) _j('p$i', adv: 'x'),
        for (var i = 0; i < 5; i++)
          _j('d$i', adv: 'x', side: RepresentationSide.defendant),
      ];
      final item = engine.scoreAdvocate(
        advocate: _adv,
        ctx: _ctx,
        filters: const SearchFilters(side: SideFilter.responding),
        judgments: js,
        benchJudgeIds: const [],
      )!;
      expect(
        item.metrics.comparableIds.every((id) => id.startsWith('d')),
        isTrue,
      );
    });

    test('time range excludes older matters', () {
      final js = [
        for (var i = 0; i < 5; i++) _j('new$i', adv: 'x', yearsAgo: 1),
        for (var i = 0; i < 5; i++) _j('old$i', adv: 'x', yearsAgo: 8),
      ];
      final item = engine.scoreAdvocate(
        advocate: _adv,
        ctx: _ctx,
        filters: const SearchFilters(yearsBack: 3),
        judgments: js,
        benchJudgeIds: const [],
      )!;
      expect(item.metrics.comparableIds.length, 5);
    });

    test('methodology version changes with every weight change', () {
      const w = ScoringWeights();
      final w2 = w.copyWith(forum: 0.25);
      expect(w2.methodologyVersion, isNot(w.methodologyVersion));
    });
  });
}
