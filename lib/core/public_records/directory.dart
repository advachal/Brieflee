import 'case_type_subjects.dart';
import 'knowledge.dart';
import 'public_records.dart';

/// Real counsel statistics from the public records.
class CounselStat {
  CounselStat(this.id, this.name);
  final int id;
  final String name;
  int appearances = 0;
  int petitionerSide = 0;
  int respondentSide = 0;
  int senior = 0;
  int government = 0;

  /// Decisions whose full text has been read and outcome classified.
  int read = 0;
  int wins = 0;
  int losses = 0;
  DateTime? lastSeen;

  int get decided => wins + losses;

  /// Wins over decided outcomes, smoothed toward 50% (as in Ask).
  double get smoothedRate => (wins + 5) / (decided + 10);

  /// Mostly appears for the State, a public body or as government counsel.
  bool get isGovernment => government * 2 > appearances;
}

class JudgeStat {
  JudgeStat(this.id, this.name);
  final int id;
  final String name;
  int decisions = 0;
  int judgments = 0;
  int read = 0;
  int petitionerOutcomes = 0;
  int respondentOutcomes = 0;
  DateTime? lastSeen;
}

/// One live-search suggestion.
sealed class QuickHit {
  const QuickHit();
}

class CounselHit extends QuickHit {
  const CounselHit(this.stat);
  final CounselStat stat;
}

class JudgeHit extends QuickHit {
  const JudgeHit(this.stat);
  final JudgeStat stat;
}

class CaseHit extends QuickHit {
  const CaseHit(this.record);
  final CourtRecord record;
}

class SubjectHit extends QuickHit {
  const SubjectHit(this.subject, this.count);
  final SubjectArea subject;
  final int count;
}

class QuickResults {
  const QuickResults({
    required this.subjects,
    required this.counsel,
    required this.judges,
    required this.cases,
  });
  static const empty = QuickResults(
    subjects: [],
    counsel: [],
    judges: [],
    cases: [],
  );
  final List<SubjectHit> subjects;
  final List<CounselHit> counsel;
  final List<JudgeHit> judges;
  final List<CaseHit> cases;
  bool get isEmpty =>
      subjects.isEmpty && counsel.isEmpty && judges.isEmpty && cases.isEmpty;
}

/// Directory of real counsel and judges, with live name search.
///
/// Built once from the snapshot. Per-subject counsel statistics are computed
/// on demand and cached. Names are matched by spelling; nothing is invented.
class RecordsDirectory {
  RecordsDirectory(this.snapshot) {
    final s = snapshot;
    _subjectOfType = [
      for (final t in s.caseTypes)
        subjectAreas.where((a) => a.matches(t)).map((a) => a.id).firstOrNull,
    ];
    counsel = _counselStats(null);
    judges = [
      for (var i = 0; i < s.judges.length; i++) JudgeStat(i, s.judges[i]),
    ];
    for (final r in s.records) {
      final o = s.outcomeOf(r);
      final read = s.knowledgeFor(r) != null;
      final sid = _subjectOfType[r.caseTypeId];
      if (sid != null) subjectCounts[sid] = (subjectCounts[sid] ?? 0) + 1;
      for (final j in r.judgeIds) {
        final st = judges[j];
        st.decisions++;
        if (r.docType == RecordDocType.judgment) st.judgments++;
        if (read) st.read++;
        if (o == RecordOutcome.petitioner) st.petitionerOutcomes++;
        if (o == RecordOutcome.respondent) st.respondentOutcomes++;
        if (st.lastSeen == null || r.date.isAfter(st.lastSeen!)) {
          st.lastSeen = r.date;
        }
      }
    }
    for (final c in counsel) {
      if (c.appearances == 0) continue;
      for (final tok in _nameTokens(c.name)) {
        (_counselIndex[tok] ??= []).add(c.id);
      }
    }
    for (final j in judges) {
      for (final tok in _nameTokens(_bareJudge(j.name))) {
        (_judgeIndex[tok] ??= []).add(j.id);
      }
    }
  }

  final PublicRecordsSnapshot snapshot;
  late final List<String?> _subjectOfType;

  /// All counsel, indexed by counsel id.
  late final List<CounselStat> counsel;

  /// All judges, indexed by judge id.
  late final List<JudgeStat> judges;

  /// Decisions per subject id.
  final Map<String, int> subjectCounts = {};

  final Map<String, List<int>> _counselIndex = {};
  final Map<String, List<int>> _judgeIndex = {};
  final Map<String, List<CounselStat>> _bySubject = {};

  String? subjectOf(CourtRecord r) => _subjectOfType[r.caseTypeId];

  static String _bareJudge(String n) =>
      n.replaceFirst(RegExp(r'^(Acting )?(Chief )?Justice '), '');

  static Iterable<String> _nameTokens(String n) =>
      n.toLowerCase().split(RegExp(r'[^a-z]+')).where((p) => p.length > 1);

  List<CounselStat> _counselStats(String? subjectId) {
    final s = snapshot;
    final out = [
      for (var i = 0; i < s.counselCount; i++) CounselStat(i, s.counselName(i)),
    ];
    for (final r in s.records) {
      if (subjectId != null && _subjectOfType[r.caseTypeId] != subjectId) {
        continue;
      }
      final o = s.outcomeOf(r);
      final read = s.knowledgeFor(r) != null;
      final seen = <int>{};
      for (final a in s.counselFor(r)) {
        if (!seen.add(a.counselId) || a.counselId >= out.length) continue;
        final c = out[a.counselId];
        c.appearances++;
        final pet = a.side == RecordSide.petitioner;
        pet ? c.petitionerSide++ : c.respondentSide++;
        if (a.role == CounselRole.senior) c.senior++;
        if (a.role == CounselRole.government) c.government++;
        if (c.lastSeen == null || r.date.isAfter(c.lastSeen!)) {
          c.lastSeen = r.date;
        }
        if (!read) continue;
        c.read++;
        if (o.eligible) {
          (o == RecordOutcome.petitioner) == pet ? c.wins++ : c.losses++;
        }
      }
    }
    return out;
  }

  /// Counsel statistics restricted to one subject (cached).
  List<CounselStat> counselFor(String? subjectId) => subjectId == null
      ? counsel
      : _bySubject.putIfAbsent(subjectId, () => _counselStats(subjectId));

  /// Counsel ranked by evidence: decided wins first, then smoothed rate.
  /// Government counsel are left out, as in Ask.
  List<CounselStat> topCounsel({String? subjectId, int minDecided = 3}) {
    final list = [
      for (final c in counselFor(subjectId))
        if (!c.isGovernment && c.decided >= minDecided && c.wins > 0) c,
    ];
    list.sort((a, b) {
      final r = b.smoothedRate.compareTo(a.smoothedRate);
      return r != 0 ? r : b.wins.compareTo(a.wins);
    });
    return list;
  }

  List<int> _match(Map<String, List<int>> index, String query) {
    final toks = _nameTokens(query).toList();
    if (toks.isEmpty) return const [];
    Set<int>? acc;
    for (final t in toks) {
      final ids = <int>{};
      for (final e in index.entries) {
        if (e.key.startsWith(t)) ids.addAll(e.value);
      }
      acc = acc == null ? ids : acc.intersection(ids);
      if (acc.isEmpty) return const [];
    }
    return acc!.toList();
  }

  /// Counsel whose name matches every word of [query] (word prefixes).
  List<CounselStat> searchCounsel(String query, {String? subjectId}) {
    final stats = counselFor(subjectId);
    final list = [
      for (final id in _match(_counselIndex, query))
        if (stats[id].appearances > 0) stats[id],
    ]..sort((a, b) => b.appearances.compareTo(a.appearances));
    return list;
  }

  List<JudgeStat> searchJudges(String query) =>
      [for (final id in _match(_judgeIndex, query)) judges[id]]
        ..sort((a, b) => b.decisions.compareTo(a.decisions));

  static final _caseNo = RegExp(r'(\d{1,6})\s*(?:/|of)\s*(\d{4})');

  /// Live suggestions while the user types: subjects, counsel, judges and
  /// cases (by case number or party name).
  QuickResults quickSearch(String query, {int limit = 5}) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return QuickResults.empty;
    final subjects = <SubjectHit>[
      for (final a in subjectAreas)
        if ((subjectCounts[a.id] ?? 0) > 0 &&
            (a.label.toLowerCase().contains(q) ||
                a.keywords.any((k) => k.startsWith(q) || q.contains(k))))
          SubjectHit(a, subjectCounts[a.id]!),
    ].take(3).toList();
    final counsel = [
      for (final c in searchCounsel(q).take(limit)) CounselHit(c),
    ];
    final judges = [for (final j in searchJudges(q).take(3)) JudgeHit(j)];
    final cases = <CaseHit>[];
    final m = _caseNo.firstMatch(q);
    if (m != null) {
      final no = m.group(1)!, yr = int.parse(m.group(2)!);
      for (final r in snapshot.records) {
        if (r.regYear == yr && r.caseNo.replaceFirst(RegExp('^0+'), '') == no) {
          cases.add(CaseHit(r));
          if (cases.length >= limit) break;
        }
      }
    } else if (q.length >= 4) {
      for (final r in snapshot.records) {
        if (r.petitioner.toLowerCase().contains(q) ||
            r.respondent.toLowerCase().contains(q)) {
          cases.add(CaseHit(r));
          if (cases.length >= limit) break;
        }
      }
    }
    return QuickResults(
      subjects: subjects,
      counsel: counsel,
      judges: judges,
      cases: cases,
    );
  }
}
