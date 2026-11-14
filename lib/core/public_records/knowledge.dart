/// The knowledge layer built from the text of official judgments
/// (tool/knowledge/build_knowledge.py). Bundled in the app for the pilot
/// subjects; the full-text RAG service in server/ uses the same build.
library;

/// What the operative part of an order says happened.
enum RecordOutcome {
  petitioner('p', 'Petitioner side succeeded', true),
  respondent('r', 'Respondent side succeeded', true),
  appointed('a', 'Arbitrator appointed (not counted)', false),
  consent('c', 'By consent or unopposed (not counted)', false),
  partly('m', 'Partly allowed (not counted)', false),
  settled('s', 'Settled (not counted)', false),
  withdrawn('w', 'Withdrawn (not counted)', false),
  infructuous('i', 'Infructuous (not counted)', false),
  interim('t', 'Interim order (not counted)', false),
  unknown('u', 'Outcome not determined', false);

  const RecordOutcome(this.code, this.label, this.eligible);
  final String code;
  final String label;

  /// Only clear wins and losses count toward favourable rates.
  final bool eligible;

  static RecordOutcome fromCode(String c) =>
      values.firstWhere((o) => o.code == c, orElse: () => unknown);
}

class KnowledgeEntry {
  const KnowledgeEntry({
    required this.outcome,
    required this.evidence,
    required this.terms,
    required this.statutes,
    required this.counsel,
    required this.pages,
  });

  final RecordOutcome outcome;

  /// The exact operative sentence the outcome was read from.
  final String evidence;
  final List<String> terms;
  final List<String> statutes;

  /// Counsel from the full judgment header: [counselId, side, role].
  final List<List<dynamic>> counsel;
  final int pages;
}

class KnowledgeLayer {
  KnowledgeLayer({
    required this.entries,
    required this.extraCounselStart,
    required this.extraCounsel,
    required this.outcomeCounts,
  });

  final Map<String, KnowledgeEntry> entries;
  final int extraCounselStart;
  final List<String> extraCounsel;
  final Map<String, int> outcomeCounts;

  static final empty = KnowledgeLayer(
    entries: const {},
    extraCounselStart: 1 << 30,
    extraCounsel: const [],
    outcomeCounts: const {},
  );

  int get documents => entries.length;

  factory KnowledgeLayer.fromJson(Map<String, dynamic> j) {
    final recs = j['records'] as Map<String, dynamic>;
    return KnowledgeLayer(
      entries: {
        for (final e in recs.entries)
          e.key: KnowledgeEntry(
            outcome: RecordOutcome.fromCode((e.value as List)[0] as String),
            evidence: e.value[1] as String,
            terms: (e.value[2] as List).cast<String>(),
            statutes: (e.value[3] as List).cast<String>(),
            counsel: (e.value[4] as List).cast<List<dynamic>>(),
            pages: e.value[5] as int,
          ),
      },
      extraCounselStart: j['extra_counsel_start'] as int,
      extraCounsel: (j['extra_counsel'] as List).cast<String>(),
      outcomeCounts: ((j['meta'] as Map)['outcome_counts'] as Map).map(
        (k, v) => MapEntry(k as String, v as int),
      ),
    );
  }
}
