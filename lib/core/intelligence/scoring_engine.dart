import 'dart:math' as math;

import '../models/models.dart';

/// What the user's matter looks like after analysis and bench identification.
class MatchContext {
  const MatchContext({
    required this.courtId,
    required this.category,
    required this.stage,
    required this.statutes,
    required this.benchJudgeIds,
  });

  final String? courtId;
  final String category;
  final CaseStage stage;
  final List<String> statutes;
  final List<String> benchJudgeIds;
}

/// Transparent, versioned advocate scoring (blueprint section 7).
///
/// All six components are normalised to 0..1. The engine never forces a
/// ranking: advocates below the evidence threshold are returned separately
/// as "insufficient verified evidence".
class ScoringEngine {
  const ScoringEngine({this.weights = const ScoringWeights(), this.fixedAsOf});

  final ScoringWeights weights;

  /// Reference date for recency and time-range filters; defaults to now.
  final DateTime? fixedAsOf;

  // Normalisation caps, tuned to the demo dataset. To be calibrated with
  // reviewed legal data.
  static const comparableCap = 10.0;
  static const forumCap = 16.0;
  static const judgeCap = 5.0;
  static const recencyHalfLifeYears = 3.0;

  /// Bayesian smoothing toward 50%, so that 8/10 does not automatically
  /// outrank 70/100.
  static const outcomePriorStrength = 10.0;
  static const minEligibleOutcomes = 3;

  DateTime get asOf => fixedAsOf ?? DateTime.now();

  /// Relevance of one judgment to the user's matter (0..1).
  double relevance(Judgment j, MatchContext ctx, Set<String> categories) {
    var r = 0.0;
    if (categories.contains(j.category)) r += 0.55;
    if (j.stage == ctx.stage) r += 0.25;
    if (ctx.statutes.isNotEmpty) {
      final overlap = j.statutes.where(ctx.statutes.contains).length;
      r += 0.20 * (overlap / ctx.statutes.length);
    } else {
      r += 0.10;
    }
    return r.clamp(0.0, 1.0);
  }

  bool isComparable(Judgment j, MatchContext ctx, SearchFilters f) {
    final cats = f.categories.isEmpty ? {ctx.category} : f.categories;
    if (!cats.contains(j.category)) return false;
    if (f.stage != null && j.stage != f.stage) return false;
    return true;
  }

  Recommendation recommend({
    required String id,
    required String matterId,
    required MatchContext ctx,
    required SearchFilters filters,
    required List<Advocate> advocates,
    required List<Judgment> judgments,
    required Map<String, int> mentionOnlyCounts,
    required List<SourceRun> sourceRuns,
  }) {
    final ranked = <RecommendationItem>[];
    final insufficient = <RecommendationItem>[];
    final bench = filters.judgeIds.isNotEmpty
        ? filters.judgeIds.toList()
        : ctx.benchJudgeIds;

    for (final adv in advocates) {
      final item = scoreAdvocate(
        advocate: adv,
        ctx: ctx,
        filters: filters,
        judgments: judgments,
        benchJudgeIds: bench,
        mentionOnly: mentionOnlyCounts[adv.id] ?? 0,
      );
      if (item == null) continue;
      (item.insufficient ? insufficient : ranked).add(item);
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    insufficient.sort(
      (a, b) => b.metrics.comparableIds.length.compareTo(
        a.metrics.comparableIds.length,
      ),
    );

    return Recommendation(
      id: id,
      matterId: matterId,
      createdAt: asOf,
      methodologyVersion: weights.methodologyVersion,
      filters: filters,
      ranked: ranked,
      insufficient: insufficient,
      sourceRuns: sourceRuns,
      benchJudgeIds: bench,
    );
  }

  /// Returns null when the advocate has no comparable matters at all.
  RecommendationItem? scoreAdvocate({
    required Advocate advocate,
    required MatchContext ctx,
    required SearchFilters filters,
    required List<Judgment> judgments,
    required List<String> benchJudgeIds,
    int mentionOnly = 0,
  }) {
    final cutoff = DateTime(
      asOf.year - filters.yearsBack,
      asOf.month,
      asOf.day,
    );
    final cats = filters.categories.isEmpty
        ? {ctx.category}
        : filters.categories;

    final pool = <Judgment>[];
    for (final j in judgments) {
      final a = j.appearanceOf(advocate.id);
      if (a == null) continue;
      if (!filters.side.accepts(a.side)) continue;
      if (j.date.isBefore(cutoff)) continue;
      if (filters.courtId != null && j.courtId != filters.courtId) continue;
      pool.add(j);
    }

    final comparable = pool
        .where((j) => isComparable(j, ctx, filters))
        .toList();
    if (comparable.isEmpty) return null;

    final verified = pool
        .where((j) => j.appearanceOf(advocate.id)!.isVerified)
        .toList();
    final comparableVerified = comparable
        .where((j) => j.appearanceOf(advocate.id)!.isVerified)
        .toList();
    final forumCourt = filters.courtId ?? ctx.courtId;
    final forum = forumCourt == null
        ? <Judgment>[]
        : pool.where((j) => j.courtId == forumCourt).toList();
    final beforeBench = benchJudgeIds.isEmpty
        ? <Judgment>[]
        : pool
              .where((j) => j.benchJudgeIds.any(benchJudgeIds.contains))
              .toList();

    // Outcomes only count verified comparable appearances with an eligible
    // disposition. Everything else is listed as excluded.
    final eligible = <Judgment>[];
    final fav = <Judgment>[];
    final unf = <Judgment>[];
    final mixed = <Judgment>[];
    final excluded = <Judgment>[];
    for (final j in comparable) {
      final a = j.appearanceOf(advocate.id)!;
      if (!a.isVerified || !j.disposition.eligible) {
        excluded.add(j);
        continue;
      }
      eligible.add(j);
      switch (j.disposition.outcomeFor(a.side)) {
        case PartyOutcome.favorable:
          fav.add(j);
        case PartyOutcome.unfavorable:
          unf.add(j);
        case PartyOutcome.mixed:
          mixed.add(j);
        case PartyOutcome.excluded:
          break;
      }
    }

    final relSum = comparable.fold<double>(
      0,
      (s, j) => s + relevance(j, ctx, cats),
    );
    final c = math.min(1.0, relSum / comparableCap);
    final f = math.min(1.0, forum.length / forumCap);
    final jScore = math.min(1.0, beforeBench.length / judgeCap);
    final o =
        (fav.length + 0.5 * mixed.length + outcomePriorStrength * 0.5) /
        (eligible.length + outcomePriorStrength);
    final r =
        comparable.fold<double>(0, (s, j) {
          final years = asOf.difference(j.date).inDays / 365.25;
          return s + math.pow(0.5, years / recencyHalfLifeYears);
        }) /
        comparable.length;
    final v = pool.isEmpty ? 0.0 : verified.length / pool.length;

    final judgeApplied = benchJudgeIds.isNotEmpty;
    final activeTotal = judgeApplied
        ? weights.total
        : weights.total - weights.judge;
    final raw =
        weights.comparable * c +
        weights.forum * f +
        (judgeApplied ? weights.judge * jScore : 0) +
        weights.outcome * o +
        weights.recency * r +
        weights.roleVerification * v;
    final score = activeTotal <= 0 ? 0.0 : (raw / activeTotal) * 100;

    final metrics = AdvocateMetrics(
      searchHits: pool.length + mentionOnly,
      mentionOnly: mentionOnly,
      allAppearanceIds: _ids(pool),
      verifiedAppearanceIds: _ids(verified),
      comparableIds: _ids(comparable),
      forumIds: _ids(forum),
      judgeIds: _ids(beforeBench),
      eligibleIds: _ids(eligible),
      favorableIds: _ids(fav),
      unfavorableIds: _ids(unf),
      mixedIds: _ids(mixed),
      excludedIds: _ids(excluded),
    );

    final isInsufficient =
        comparableVerified.length < filters.minVerifiedComparable ||
        eligible.length < minEligibleOutcomes;

    final reliability = isInsufficient
        ? EvidenceReliability.insufficient
        : (eligible.length >= 10 && v >= 0.85)
        ? EvidenceReliability.high
        : (eligible.length >= 6 && v >= 0.7)
        ? EvidenceReliability.moderate
        : EvidenceReliability.low;

    final reasons = <String>[
      '${comparable.length} comparable ${ctx.category.toLowerCase()} matters '
          '(${comparableVerified.length} with verified appearance).',
      if (forum.isNotEmpty) '${forum.length} matters in the same forum.',
      if (judgeApplied)
        beforeBench.isEmpty
            ? 'No recorded matters before the identified bench.'
            : '${beforeBench.length} matters before a judge on the identified bench.',
      if (eligible.isNotEmpty)
        '${fav.length} favorable, ${unf.length} unfavorable and '
            '${mixed.length} mixed of ${eligible.length} eligible outcomes.',
    ];

    final limitations = <String>[
      if (excluded.isNotEmpty)
        '${excluded.length} comparable matters excluded from outcome rate '
            '(settled, withdrawn, procedural, indeterminate or unverified role).',
      if (eligible.length < 10)
        'Small sample: ${eligible.length} eligible outcomes.',
      if (!judgeApplied)
        'No bench identified, so judge experience was not scored.',
      if (mentionOnly > 0)
        '$mentionOnly search mentions were not counted as appearances.',
    ];

    final headline = isInsufficient
        ? 'Insufficient verified evidence to recommend confidently.'
        : _headline(
            ctx,
            comparable.length,
            forum.length,
            beforeBench.length,
            judgeApplied,
          );

    return RecommendationItem(
      advocate: advocate,
      score: score,
      components: ScoreComponents(
        comparable: c,
        forum: f,
        judge: jScore,
        outcome: o,
        recency: r,
        roleVerification: v,
        judgeApplied: judgeApplied,
      ),
      metrics: metrics,
      reliability: reliability,
      headline: headline,
      reasons: reasons,
      limitations: limitations,
      insufficient: isInsufficient,
    );
  }

  static List<String> _ids(List<Judgment> js) => [for (final j in js) j.id];

  static String _headline(
    MatchContext ctx,
    int comparable,
    int forum,
    int bench,
    bool judgeApplied,
  ) {
    final parts = <String>[
      '$comparable comparable ${ctx.category.toLowerCase()} matters',
    ];
    if (forum > 0) parts.add('$forum in this forum');
    if (judgeApplied && bench > 0) parts.add('$bench before the listed bench');
    return 'Strong documented experience: ${parts.join(', ')}.';
  }
}
