import '../models/models.dart';

/// A raw record as returned by one source adapter, before deduplication.
class RawJudgmentRecord {
  const RawJudgmentRecord({required this.source, required this.judgment});

  final SourceType source;
  final Judgment judgment;
}

/// Merges records for the same case from different repositories into one
/// judgment that keeps every source reference (blueprint section 6).
///
/// When a repository disagrees with an official record, the official record
/// wins and the judgment is flagged with a conflict note.
class JudgmentDeduplicator {
  const JudgmentDeduplicator();

  static String key(Judgment j) {
    final caseNo = j.caseNumber.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final d = j.date;
    return '${j.courtId}|$caseNo|${d.year}-${d.month}-${d.day}';
  }

  List<Judgment> merge(List<RawJudgmentRecord> records) {
    final groups = <String, List<RawJudgmentRecord>>{};
    for (final r in records) {
      groups.putIfAbsent(key(r.judgment), () => []).add(r);
    }
    return [for (final g in groups.values) _mergeGroup(g)];
  }

  Judgment _mergeGroup(List<RawJudgmentRecord> group) {
    final official = group.where((r) => r.source == SourceType.official);
    final base = official.isNotEmpty
        ? official.first.judgment
        : group.first.judgment;

    final sources = <JudgmentSourceRef>[];
    final seen = <SourceType>{};
    for (final r in group) {
      for (final s in r.judgment.sources) {
        if (seen.add(s.type)) sources.add(s);
      }
    }

    String? conflict = base.conflictNote;
    final citations = group.map((r) => r.judgment.citation).toSet();
    if (citations.length > 1) {
      conflict =
          'Citation differs across sources (${citations.join(' / ')}). '
          '${official.isNotEmpty ? 'Official record used.' : 'Flagged for review.'}';
    }

    return Judgment(
      id: base.id,
      title: base.title,
      citation: base.citation,
      caseNumber: base.caseNumber,
      courtId: base.courtId,
      benchJudgeIds: base.benchJudgeIds,
      date: base.date,
      category: base.category,
      statutes: base.statutes,
      stage: base.stage,
      disposition: base.disposition,
      dispositionConfidence: base.dispositionConfidence,
      reviewStatus: base.reviewStatus,
      appearances: base.appearances,
      sources: sources,
      passages: base.passages,
      summary: base.summary,
      conflictNote: conflict,
    );
  }
}
