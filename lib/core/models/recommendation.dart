import 'advocate.dart';
import 'enums.dart';

/// Configurable weights for S = wC·C + wF·F + wJ·J + wO·O + wR·R + wV·V.
class ScoringWeights {
  const ScoringWeights({
    this.comparable = 0.30,
    this.forum = 0.20,
    this.judge = 0.15,
    this.outcome = 0.20,
    this.recency = 0.10,
    this.roleVerification = 0.05,
    this.revision = 1,
  });

  final double comparable;
  final double forum;
  final double judge;
  final double outcome;
  final double recency;
  final double roleVerification;

  /// Bumped whenever an administrator changes a weight, so that every saved
  /// recommendation can be reproduced with the exact methodology it used.
  final int revision;

  double get total =>
      comparable + forum + judge + outcome + recency + roleVerification;

  String get methodologyVersion => 'cm-score-0.1.$revision-demo';

  ScoringWeights copyWith({
    double? comparable,
    double? forum,
    double? judge,
    double? outcome,
    double? recency,
    double? roleVerification,
  }) => ScoringWeights(
    comparable: comparable ?? this.comparable,
    forum: forum ?? this.forum,
    judge: judge ?? this.judge,
    outcome: outcome ?? this.outcome,
    recency: recency ?? this.recency,
    roleVerification: roleVerification ?? this.roleVerification,
    revision: revision + 1,
  );

  Map<String, dynamic> toJson() => {
    'comparable': comparable,
    'forum': forum,
    'judge': judge,
    'outcome': outcome,
    'recency': recency,
    'role_verification': roleVerification,
    'methodology_version': methodologyVersion,
  };
}

/// Normalised (0..1) score components.
class ScoreComponents {
  const ScoreComponents({
    required this.comparable,
    required this.forum,
    required this.judge,
    required this.outcome,
    required this.recency,
    required this.roleVerification,
    required this.judgeApplied,
  });

  final double comparable;
  final double forum;
  final double judge;
  final double outcome;
  final double recency;
  final double roleVerification;

  /// False when no bench was identified, so the judge weight was redistributed.
  final bool judgeApplied;

  Map<String, dynamic> toJson() => {
    'comparable': comparable,
    'forum': forum,
    'judge': judge,
    'outcome': outcome,
    'recency': recency,
    'role_verification': roleVerification,
    'judge_applied': judgeApplied,
  };
}

/// Case-level counts. Every count is backed by the judgment ids it contains,
/// so tapping a number in the UI can list exactly those cases.
class AdvocateMetrics {
  const AdvocateMetrics({
    required this.searchHits,
    required this.mentionOnly,
    required this.allAppearanceIds,
    required this.verifiedAppearanceIds,
    required this.comparableIds,
    required this.forumIds,
    required this.judgeIds,
    required this.eligibleIds,
    required this.favorableIds,
    required this.unfavorableIds,
    required this.mixedIds,
    required this.excludedIds,
  });

  final int searchHits;
  final int mentionOnly;
  final List<String> allAppearanceIds;
  final List<String> verifiedAppearanceIds;
  final List<String> comparableIds;
  final List<String> forumIds;
  final List<String> judgeIds;
  final List<String> eligibleIds;
  final List<String> favorableIds;
  final List<String> unfavorableIds;
  final List<String> mixedIds;
  final List<String> excludedIds;

  double? get favorableRate =>
      eligibleIds.isEmpty ? null : favorableIds.length / eligibleIds.length;

  Map<String, dynamic> toJson() => {
    'search_hits': searchHits,
    'mention_only': mentionOnly,
    'verified_appearance_ids': verifiedAppearanceIds,
    'comparable_ids': comparableIds,
    'forum_ids': forumIds,
    'judge_ids': judgeIds,
    'eligible_ids': eligibleIds,
    'favorable_ids': favorableIds,
    'unfavorable_ids': unfavorableIds,
    'mixed_ids': mixedIds,
    'excluded_ids': excludedIds,
  };
}

class RecommendationItem {
  const RecommendationItem({
    required this.advocate,
    required this.score,
    required this.components,
    required this.metrics,
    required this.reliability,
    required this.headline,
    required this.reasons,
    required this.limitations,
    required this.insufficient,
  });

  final Advocate advocate;

  /// Match relevance, 0–100. Shown separately from [reliability].
  final double score;
  final ScoreComponents components;
  final AdvocateMetrics metrics;
  final EvidenceReliability reliability;
  final String headline;
  final List<String> reasons;
  final List<String> limitations;
  final bool insufficient;

  Map<String, dynamic> toJson() => {
    'advocate': advocate.toJson(),
    'score': score,
    'components': components.toJson(),
    'metrics': metrics.toJson(),
    'reliability': reliability.name,
    'headline': headline,
    'reasons': reasons,
    'limitations': limitations,
    'insufficient': insufficient,
  };
}

enum SourceRunStatus {
  disabled('Not connected'),
  ok('Searched'),
  partial('Partial coverage'),
  failed('Failed');

  const SourceRunStatus(this.label);
  final String label;
}

class SourceRun {
  const SourceRun({
    required this.source,
    required this.status,
    required this.message,
    this.records = 0,
  });

  final SourceType source;
  final SourceRunStatus status;
  final String message;
  final int records;
}

class SearchFilters {
  const SearchFilters({
    this.courtId,
    this.categories = const {},
    this.stage,
    this.side = SideFilter.any,
    this.judgeIds = const {},
    this.yearsBack = 10,
    this.minVerifiedComparable = 4,
  });

  final String? courtId;
  final Set<String> categories;
  final CaseStage? stage;
  final SideFilter side;
  final Set<String> judgeIds;
  final int yearsBack;
  final int minVerifiedComparable;

  SearchFilters copyWith({
    String? courtId,
    bool clearCourt = false,
    Set<String>? categories,
    CaseStage? stage,
    bool clearStage = false,
    SideFilter? side,
    Set<String>? judgeIds,
    int? yearsBack,
    int? minVerifiedComparable,
  }) => SearchFilters(
    courtId: clearCourt ? null : (courtId ?? this.courtId),
    categories: categories ?? this.categories,
    stage: clearStage ? null : (stage ?? this.stage),
    side: side ?? this.side,
    judgeIds: judgeIds ?? this.judgeIds,
    yearsBack: yearsBack ?? this.yearsBack,
    minVerifiedComparable: minVerifiedComparable ?? this.minVerifiedComparable,
  );

  Map<String, dynamic> toJson() => {
    'court_id': courtId,
    'categories': categories.toList(),
    'stage': stage?.name,
    'side': side.name,
    'judge_ids': judgeIds.toList(),
    'years_back': yearsBack,
    'min_verified_comparable': minVerifiedComparable,
  };
}

class Recommendation {
  const Recommendation({
    required this.id,
    required this.matterId,
    required this.createdAt,
    required this.methodologyVersion,
    required this.filters,
    required this.ranked,
    required this.insufficient,
    required this.sourceRuns,
    required this.benchJudgeIds,
  });

  final String id;
  final String matterId;
  final DateTime createdAt;
  final String methodologyVersion;
  final SearchFilters filters;
  final List<RecommendationItem> ranked;
  final List<RecommendationItem> insufficient;
  final List<SourceRun> sourceRuns;
  final List<String> benchJudgeIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'matter_id': matterId,
    'created_at': createdAt.toIso8601String(),
    'methodology_version': methodologyVersion,
    'filters': filters.toJson(),
    'ranked': ranked.map((r) => r.toJson()).toList(),
    'insufficient': insufficient.map((r) => r.toJson()).toList(),
    'bench_judge_ids': benchJudgeIds,
  };
}
