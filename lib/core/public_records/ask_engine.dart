import 'dart:math' as math;

import 'case_type_subjects.dart';
import 'knowledge.dart';
import 'public_records.dart';

/// How a question was read. Shown to the user so they can see (and correct)
/// what the system searched for.
class AskInterpretation {
  const AskInterpretation({
    required this.subjects,
    required this.sections,
    required this.judgeIds,
    required this.counselIds,
    required this.years,
    required this.caseNumber,
    required this.terms,
    required this.side,
    this.courts = const [],
  });

  final List<SubjectArea> subjects;
  final List<String> sections;
  final List<int> judgeIds;
  final List<int> counselIds;
  final List<int> years;
  final ({String no, int year})? caseNumber;
  final List<String> terms;

  /// The side the user is on, if the question says so.
  final RecordSide? side;

  /// Courts named in the question (indexes into the snapshot's courts).
  final List<int> courts;

  bool get isEmpty =>
      subjects.isEmpty &&
      sections.isEmpty &&
      judgeIds.isEmpty &&
      counselIds.isEmpty &&
      years.isEmpty &&
      caseNumber == null &&
      terms.isEmpty;
}

/// Which side the user acts for, as chosen in the UI.
enum SideChoice { auto, either, petitioner, respondent }

class AskHit {
  const AskHit(this.record, this.score, this.matchedTerms);
  final CourtRecord record;
  final double score;
  final List<String> matchedTerms;
}

/// Counsel evidence computed from the retrieved, similar decisions.
class CounselEvidence {
  CounselEvidence(this.counselId, this.name);

  final int counselId;
  final String name;
  final List<int> similar = [];
  final List<int> favourable = [];
  final List<int> unfavourable = [];
  final List<int> notEligible = [];
  int petitionerSide = 0;
  int respondentSide = 0;
  double weightedWins = 0;
  double weightedEligible = 0;
  double smoothedRate = 0.5;
  double score = 0;

  int get eligible => favourable.length + unfavourable.length;
  bool get sufficient => eligible >= AskEngine.minEligible;

  /// Ranked as "won similar matters" only with enough decided outcomes,
  /// at least one win, and a favourable rate at or above even.
  bool get rankable =>
      sufficient && favourable.isNotEmpty && smoothedRate >= 0.5;
}

class JudgeCount {
  const JudgeCount(this.judgeId, this.name, this.recordIndexes);
  final int judgeId;
  final String name;
  final List<int> recordIndexes;
}

class AskAnswer {
  const AskAnswer({
    required this.question,
    required this.interpretation,
    required this.hits,
    required this.counsel,
    required this.insufficient,
    required this.judges,
    required this.withOutcomeText,
    required this.summary,
    this.generated,
  });

  final String question;
  final AskInterpretation interpretation;

  /// Similar decisions, best first.
  final List<AskHit> hits;

  /// Counsel with enough outcome-eligible similar decisions, ranked.
  final List<CounselEvidence> counsel;

  /// Counsel who appeared in similar decisions but lack eligible outcomes.
  final List<CounselEvidence> insufficient;
  final List<JudgeCount> judges;

  /// How many of the hits have their judgment text in the knowledge layer.
  final int withOutcomeText;

  /// Deterministic, factual summary built from the numbers above.
  final String summary;

  /// A grounded narrative from the knowledge service, when one is connected.
  final String? generated;
}

/// Real-time question answering over the public records and knowledge layer.
///
/// 1. Interpret the question (subjects, statute sections, bench, counsel,
///    year, side, remaining words).
/// 2. Retrieve similar decisions: BM25-style scoring over each decision's
///    key terms and statutes (from its judgment text) and party names,
///    restricted to the subject's official case types.
/// 3. Aggregate counsel: credit the winning side in outcome-eligible
///    decisions, smooth rates toward 50%, require an evidence threshold.
/// No outcome, counsel or case is invented: every number is a list of
/// decisions the user can open.
class AskEngine {
  AskEngine(this.snapshot) {
    _build();
  }

  final PublicRecordsSnapshot snapshot;

  static const minEligible = 3;
  static const priorStrength = 10.0;
  static const maxHits = 150;

  final Map<String, List<int>> _postings = {};
  final Map<String, List<int>> _counselTokens = {};
  late final List<List<String>> _judgeTokens;

  static const _stop = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'can',
    'for',
    'from',
    'has',
    'have',
    'how',
    'in',
    'is',
    'it',
    'its',
    'me',
    'my',
    'of',
    'on',
    'or',
    'our',
    'that',
    'the',
    'their',
    'this',
    'to',
    'was',
    'we',
    'were',
    'what',
    'when',
    'which',
    'who',
    'whom',
    'will',
    'with',
    'would',
    'should',
    'could',
    'you',
    'your',
    'best',
    'lawyer',
    'lawyers',
    'advocate',
    'advocates',
    'counsel',
    'find',
    'suggest',
    'recommend',
    'need',
    'needs',
    'want',
    'wants',
    'help',
    'case',
    'cases',
    'matter',
    'matters',
    'similar',
    'like',
    'delhi',
    'high',
    'court',
    'won',
    'win',
    'wins',
    'winning',
    'client',
    'clients',
    'under',
    'section',
    'sections',
    'any',
    'please',
    'give',
    'show',
    'list',
    'top',
    'good',
    'justice',
    'judge',
    'bench',
    'before',
    'about',
    'past',
    'there',
    'been',
    'did',
    'does',
    'do',
    'i',
    'am',
    'he',
    'she',
    'they',
    'them',
    'his',
    'her',
    'ltd',
    'pvt',
    'limited',
    'private',
    'ors',
    'anr',
    'haryana',
    'punjab',
    'chandigarh',
    'v',
    'vs',
    'versus',
    'against',
    'petition',
    'appeal',
    'suit',
  };

  static final _word = RegExp(r"[a-z][a-z\-]{2,}");

  static Iterable<String> _tokens(String s) => _word
      .allMatches(s.toLowerCase())
      .map((m) => m.group(0)!)
      .where((w) => !_stop.contains(w));

  void _build() {
    final k = snapshot.knowledge;
    for (final r in snapshot.records) {
      final seen = <String>{};
      for (final t in _tokens('${r.petitioner} ${r.respondent}')) {
        if (seen.add('p:$t')) (_postings['p:$t'] ??= []).add(r.index);
      }
      final e = k.entries[r.id];
      if (e != null) {
        for (final t in e.terms) {
          if (seen.add('t:$t')) (_postings['t:$t'] ??= []).add(r.index);
        }
        for (final st in e.statutes) {
          for (final t in _tokens(st)) {
            if (seen.add('t:$t')) (_postings['t:$t'] ??= []).add(r.index);
          }
          final sec = RegExp(r'^s\.(\w+) ').firstMatch(st);
          if (sec != null && seen.add('s:${sec.group(1)!.toLowerCase()}')) {
            (_postings['s:${sec.group(1)!.toLowerCase()}'] ??= []).add(r.index);
          }
        }
      }
    }
    for (var i = 0; i < snapshot.counselCount; i++) {
      final parts = snapshot
          .counselName(i)
          .toLowerCase()
          .split(RegExp(r'[^a-z]+'))
          .where((p) => p.length > 2);
      for (final p in parts) {
        (_counselTokens[p] ??= []).add(i);
      }
    }
    _judgeTokens = [
      for (final j in snapshot.judges)
        j
            .replaceFirst(RegExp(r'^(Acting )?(Chief )?Justice '), '')
            .toLowerCase()
            .split(RegExp(r'[^a-z]+'))
            .where((p) => p.length > 2)
            .toList(),
    ];
  }

  AskInterpretation interpret(String question) {
    var q = question.toLowerCase();
    // "patent illegality" is an arbitration ground, not a patent dispute.
    q = q.replaceAll('patent illegality', 'illegality');
    final subjects = [
      for (final s in subjectAreas)
        if (s.keywords.any(
          (k) => RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(q),
        ))
          s,
    ];
    final sections = {
      for (final m in RegExp(
        r'\b(?:section|sec\.?|s\.)\s*(\d+[a-z]?)\b',
      ).allMatches(q))
        m.group(1)!,
    }.toList();
    final years = {
      for (final m in RegExp(r'\b(20[12]\d)\b').allMatches(q))
        if (snapshot.years.contains(m.group(1))) int.parse(m.group(1)!),
    }.toList();
    final cn = RegExp(r'\b(\d{1,6})\s*/\s*(\d{4})\b').firstMatch(q);

    final courts = <int>[];
    for (var i = 0; i < snapshot.courts.length; i++) {
      final name = snapshot.courts[i].court.toLowerCase();
      final keys = name.contains('punjab')
          ? ['punjab', 'haryana', 'chandigarh', 'p&h']
          : (name.contains('delhi') ? ['delhi'] : <String>[]);
      if (keys.any(q.contains)) courts.add(i);
    }
    final words = _word.allMatches(q).map((m) => m.group(0)!).toSet();
    final consumed = <String>{};
    final judgeIds = <int>[];
    for (var i = 0; i < _judgeTokens.length; i++) {
      final toks = _judgeTokens[i];
      final hit = toks.where(words.contains).toList();
      if (toks.isNotEmpty &&
          (hit.length >= 2 ||
              (hit.length == toks.length && toks.length == 1))) {
        judgeIds.add(i);
        consumed.addAll(hit);
      }
    }
    final counselIds = <int>[];
    if (RegExp(r'\b(advocate|counsel|lawyer|mr|ms|adv)\b').hasMatch(q) ||
        words.length <= 6) {
      final candidates = <int, int>{};
      for (final w in words) {
        for (final c in _counselTokens[w] ?? const <int>[]) {
          candidates[c] = (candidates[c] ?? 0) + 1;
        }
      }
      for (final e in candidates.entries) {
        final n = snapshot
            .counselName(e.key)
            .toLowerCase()
            .split(RegExp(r'[^a-z]+'))
            .where((p) => p.length > 2)
            .length;
        if (n >= 2 && e.value == n) {
          counselIds.add(e.key);
          consumed.addAll(
            snapshot.counselName(e.key).toLowerCase().split(RegExp(r'[^a-z]+')),
          );
        }
      }
      counselIds.sort(
        (a, b) =>
            snapshot.appearanceCount(b).compareTo(snapshot.appearanceCount(a)),
      );
      if (counselIds.length > 3) counselIds.removeRange(3, counselIds.length);
    }
    RecordSide? side;
    if (RegExp(r'\b(respondent|defend\w*|opposing|i was sued|we were sued)\b')
        .hasMatch(q)) {
      side = RecordSide.respondent;
    } else if (RegExp(
      r'\b(petitioner|plaintiff|appellant|file|filing|challeng\w*|set aside|sue)\b',
    ).hasMatch(q)) {
      side = RecordSide.petitioner;
    }
    final subjectWords = {
      for (final s in subjects) ...s.keywords.expand((k) => k.split(' ')),
    };
    final terms = _tokens(q)
        .where(
          (t) =>
              !consumed.contains(t) &&
              !subjectWords.contains(t) &&
              !RegExp(r'^\d').hasMatch(t),
        )
        .toSet()
        .toList();
    return AskInterpretation(
      subjects: subjects,
      sections: sections,
      judgeIds: judgeIds,
      counselIds: counselIds,
      years: years,
      caseNumber: cn == null
          ? null
          : (no: cn.group(1)!, year: int.parse(cn.group(2)!)),
      terms: terms,
      side: side,
      courts: courts,
    );
  }

  bool _subjectOk(CourtRecord r, List<SubjectArea> subjects) {
    if (subjects.isEmpty) return true;
    final t = snapshot.caseTypes[r.caseTypeId];
    return subjects.any((s) => s.matches(t));
  }

  String? _lastQuestion;
  AskAnswer? _lastAnswer;

  /// Answers a typed question. [side] (the side the user acts for) overrides
  /// whatever the question implies; [SideChoice.auto] keeps the inference.
  AskAnswer ask(String question, {SideChoice side = SideChoice.auto}) {
    final key = '${side.name}|$question';
    if (key == _lastQuestion && _lastAnswer != null) return _lastAnswer!;
    final a = _ask(question, side);
    _lastQuestion = key;
    _lastAnswer = a;
    return a;
  }

  /// Turns an uploaded judgment or pleading into a query: its most
  /// distinctive terms (weighted against the knowledge layer), the statute
  /// sections it relies on, and the subject its statutes imply. Party,
  /// judge and counsel names in the document are deliberately not used.
  String documentQuery(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final lower = flat.toLowerCase();
    final n = snapshot.records.length;
    final tf = <String, int>{};
    for (final t in _tokens(lower)) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final scored = <(double, String)>[];
    tf.forEach((t, c) {
      final list = _postings['t:$t'];
      if (list == null || list.length < 2) return;
      final idf = math.log(1 + (n - list.length + 0.5) / (list.length + 0.5));
      scored.add((math.log(1 + c) * idf, t));
    });
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final secCount = <String, int>{};
    for (final m in RegExp(r'\bsections?\s+(\d+[a-z]?)\b').allMatches(lower)) {
      final sec = m.group(1)!;
      if (_postings.containsKey('s:$sec')) {
        secCount[sec] = (secCount[sec] ?? 0) + 1;
      }
    }
    final sections =
        (secCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(3)
            .map((e) => 'section ${e.key}');
    final subjects = <String>[
      if (lower.contains('arbitration and conciliation act') ||
          lower.contains('arbitral award'))
        'arbitration',
      if (RegExp(r'trade ?marks? act|patents act|copyright act|designs act')
          .hasMatch(lower))
        'intellectual property',
      if (lower.contains('commercial courts act')) 'commercial',
    ];
    return [
      ...subjects,
      ...sections,
      ...scored.take(22).map((e) => e.$2),
    ].join(' ');
  }

  AskAnswer _ask(String question, SideChoice sideChoice) {
    final parsed = interpret(question);
    final it = sideChoice == SideChoice.auto
        ? parsed
        : AskInterpretation(
            subjects: parsed.subjects,
            sections: parsed.sections,
            judgeIds: parsed.judgeIds,
            counselIds: parsed.counselIds,
            years: parsed.years,
            caseNumber: parsed.caseNumber,
            terms: parsed.terms,
            side: switch (sideChoice) {
              SideChoice.petitioner => RecordSide.petitioner,
              SideChoice.respondent => RecordSide.respondent,
              _ => null,
            },
            courts: parsed.courts,
          );
    final n = snapshot.records.length;

    // Candidate set from hard filters.
    Iterable<CourtRecord> pool = snapshot.records;
    if (it.caseNumber != null) {
      pool = pool.where(
        (r) =>
            r.caseNo == it.caseNumber!.no && r.regYear == it.caseNumber!.year,
      );
    }
    if (it.judgeIds.isNotEmpty) {
      final allowed = {
        for (final j in it.judgeIds)
          ...snapshot.recordsForJudge(j).map((r) => r.index),
      };
      pool = pool.where((r) => allowed.contains(r.index));
    }
    if (it.counselIds.isNotEmpty) {
      final allowed = {
        for (final c in it.counselIds)
          ...snapshot.recordsForCounsel(c).map((r) => r.index),
      };
      pool = pool.where((r) => allowed.contains(r.index));
    }
    if (it.years.isNotEmpty) {
      pool = pool.where((r) => it.years.contains(r.date.year));
    }
    if (it.courts.isNotEmpty) {
      pool = pool.where((r) => it.courts.contains(r.courtIndex));
    }
    pool = pool.where((r) => _subjectOk(r, it.subjects));

    // Text scoring (BM25-like idf weights over key terms, statutes, parties).
    final scores = <int, double>{};
    final matched = <int, List<String>>{};
    void addPosting(String key, double weight, String label) {
      final list = _postings[key];
      if (list == null || list.isEmpty) return;
      final idf = math.log(1 + (n - list.length + 0.5) / (list.length + 0.5));
      for (final i in list) {
        scores[i] = (scores[i] ?? 0) + idf * weight;
        (matched[i] ??= []).add(label);
      }
    }

    for (final t in it.terms) {
      addPosting('t:$t', 1.0, t);
      addPosting('p:$t', 0.8, t);
    }
    for (final s in it.sections) {
      addPosting('s:$s', 1.6, 'section $s');
    }

    final hasText = it.terms.isNotEmpty || it.sections.isNotEmpty;
    var hits = <AskHit>[];
    for (final r in pool) {
      final s = scores[r.index];
      if (hasText && s == null) continue;
      final known = snapshot.knowledge.entries.containsKey(r.id);
      hits.add(
        AskHit(r, (s ?? 0) + (known ? 0.5 : 0), matched[r.index] ?? const []),
      );
    }
    // If the words matched nothing, fall back to the structured filters alone.
    var fellBack = false;
    if (hits.isEmpty &&
        hasText &&
        (it.subjects.isNotEmpty ||
            it.judgeIds.isNotEmpty ||
            it.counselIds.isNotEmpty ||
            it.years.isNotEmpty ||
            it.caseNumber != null)) {
      fellBack = true;
      hits = [
        for (final r in pool)
          AskHit(
            r,
            snapshot.knowledge.entries.containsKey(r.id) ? 0.5 : 0,
            const [],
          ),
      ];
    }
    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : b.record.date.compareTo(a.record.date);
    });
    final total = hits.length;
    if (hits.length > maxHits) hits = hits.sublist(0, maxHits);

    // Counsel evidence from the similar decisions.
    final top = hits.isEmpty ? 1.0 : math.max(hits.first.score, 1e-6);
    final ev = <int, CounselEvidence>{};
    var withText = 0;
    for (final h in hits) {
      final r = h.record;
      final outcome = snapshot.outcomeOf(r);
      if (snapshot.knowledge.entries.containsKey(r.id)) withText++;
      final sim = top <= 1e-6 ? 1.0 : math.max(h.score / top, 0.05);
      final seen = <int>{};
      for (final a in snapshot.counselFor(r)) {
        if (a.role == CounselRole.government || !seen.add(a.counselId)) {
          continue;
        }
        final e = ev[a.counselId] ??= CounselEvidence(
          a.counselId,
          snapshot.counselName(a.counselId),
        );
        e.similar.add(r.index);
        if (a.side == RecordSide.petitioner) {
          e.petitionerSide++;
        } else {
          e.respondentSide++;
        }
        if (outcome.eligible) {
          final won =
              (outcome == RecordOutcome.petitioner) ==
              (a.side == RecordSide.petitioner);
          (won ? e.favourable : e.unfavourable).add(r.index);
          e.weightedEligible += sim;
          if (won) e.weightedWins += sim;
        } else {
          e.notEligible.add(r.index);
        }
      }
    }
    for (final e in ev.values) {
      e.smoothedRate =
          (e.weightedWins + 0.5 * priorStrength) /
          (e.weightedEligible + priorStrength);
      final sideFit = it.side == null
          ? 1.0
          : (it.side == RecordSide.petitioner
                    ? e.petitionerSide
                    : e.respondentSide) /
                math.max(1, e.petitionerSide + e.respondentSide);
      final relevance = math.min(e.similar.length / 10.0, 1.0);
      e.score =
          100 * (0.45 * e.smoothedRate + 0.35 * relevance + 0.20 * sideFit);
    }
    final all = ev.values.toList()
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : b.similar.length.compareTo(a.similar.length);
      });
    final ranked = all.where((e) => e.rankable).take(12).toList();
    final insufficient =
        (all.where((e) => !e.sufficient).toList()
              ..sort((a, b) => b.similar.length.compareTo(a.similar.length)))
            .take(12)
            .toList();

    final jc = <int, List<int>>{};
    for (final h in hits) {
      for (final j in h.record.judgeIds) {
        (jc[j] ??= []).add(h.record.index);
      }
    }
    final judges = [
      for (final e in jc.entries)
        JudgeCount(e.key, snapshot.judges[e.key], e.value),
    ]..sort((a, b) => b.recordIndexes.length.compareTo(a.recordIndexes.length));

    return AskAnswer(
      question: question,
      interpretation: it,
      hits: hits,
      counsel: ranked,
      insufficient: insufficient,
      judges: judges.take(8).toList(),
      withOutcomeText: withText,
      summary: _summary(it, total, hits, ranked, judges, withText, fellBack),
    );
  }

  String _summary(
    AskInterpretation it,
    int total,
    List<AskHit> hits,
    List<CounselEvidence> ranked,
    List<JudgeCount> judges,
    int withText,
    bool fellBack,
  ) {
    if (total == 0) {
      return 'No decision in the ${snapshot.yearRange} records matches this question. '
          'Try naming the subject (for example arbitration, trademark, bail), a statute section, or a party.';
    }
    final b = StringBuffer();
    final scope = it.subjects.isEmpty
        ? ''
        : ' in ${it.subjects.map((s) => s.label.toLowerCase()).join(' / ')}';
    b.write(
      '${_fmt(total)} decision${total == 1 ? '' : 's'}$scope${it.courts.isEmpty ? '' : ' of the ${it.courts.map((c) => snapshot.courts[c].court).join(' and ')}'} '
      'from ${snapshot.yearRange} match${total == 1 ? 'es' : ''}',
    );
    if (fellBack) {
      b.write(
        ' (none mentioned your exact words, so these match the subject and filters only)',
      );
    }
    b.write('. ');
    if (total > hits.length) {
      b.write('The ${hits.length} most similar are analysed below. ');
    }
    b.write(
      '$withText of them have been read in full, so their outcome is known where the order states one. ',
    );
    if (ranked.isNotEmpty) {
      final r = ranked.first;
      b.write(
        'Among counsel in these similar matters, ${r.name} has the strongest decided record: '
        '${r.favourable.length} favourable and ${r.unfavourable.length} unfavourable decided outcome'
        '${r.eligible == 1 ? '' : 's'} across ${r.similar.length} similar matter${r.similar.length == 1 ? '' : 's'}. ',
      );
    } else {
      b.write(
        'No counsel has at least $minEligible decided, comparable outcomes with a favourable record here, so none is ranked. ',
      );
    }
    if (judges.isNotEmpty) {
      b.write(
        '${judges.first.name} decided the most of these (${judges.first.recordIndexes.length}).',
      );
    }
    return b.toString();
  }

  static String _fmt(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}
