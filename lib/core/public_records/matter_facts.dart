import 'case_type_subjects.dart';
import 'public_records.dart';

/// Where the matter stands now. It decides which experience matters most.
enum MatterStage {
  unknown('Not sure'),
  fresh('About to file'),
  interim('Pending: interim relief'),
  hearing('Pending: final hearing'),
  appeal('Appeal against this decision'),
  execution('Execution or enforcement');

  const MatterStage(this.label);
  final String label;
}

/// A counsel named in the uploaded document, with the side they acted for.
class DocumentCounsel {
  const DocumentCounsel(this.name, this.side, {this.counselId});
  final String name;
  final RecordSide side;

  /// The matching name in the records, when there is one.
  final int? counselId;
}

/// The facts of a matter, extracted from a document and confirmed or
/// corrected by the user before any recommendation is made.
class MatterFacts {
  MatterFacts({
    this.court,
    this.caseNumber,
    this.petitioner,
    this.respondent,
    this.subjectId,
    this.side,
    this.stage = MatterStage.unknown,
    this.benchJudgeId,
    List<int>? decidingJudgeIds,
    List<String>? decidingJudgeNames,
    List<String>? statutes,
    List<String>? issues,
    this.relief,
    this.summary,
    List<DocumentCounsel>? counsel,
    this.source = 'device',
  }) : decidingJudgeIds = decidingJudgeIds ?? [],
       decidingJudgeNames = decidingJudgeNames ?? [],
       statutes = statutes ?? [],
       issues = issues ?? [],
       counsel = counsel ?? [];

  String? court;
  String? caseNumber;
  String? petitioner;
  String? respondent;

  /// A [SubjectArea.id].
  String? subjectId;

  /// The side the user acts for.
  RecordSide? side;
  MatterStage stage;

  /// The judge the matter is (or will be) listed before. Used as a signal
  /// for bench experience, never as a filter. It may differ from the judge
  /// who decided the uploaded order.
  int? benchJudgeId;

  /// Judges who decided the uploaded document (matched to the records).
  List<int> decidingJudgeIds;
  List<String> decidingJudgeNames;

  /// e.g. "s.34 Arbitration and Conciliation Act, 1996".
  List<String> statutes;

  /// The legal issues, in plain words.
  List<String> issues;
  String? relief;
  String? summary;
  List<DocumentCounsel> counsel;

  /// 'device' (rules in the browser) or the AI provider's name.
  String source;

  SubjectArea? get subject =>
      subjectAreas.where((s) => s.id == subjectId).firstOrNull;

  /// Statute section numbers, e.g. ["34", "37"].
  List<String> get sections => {
    for (final s in statutes)
      if (RegExp(r'^s\.(\w+)\s').firstMatch(s) case final m?)
        m.group(1)!.toLowerCase(),
  }.toList();

  MatterFacts copy() => MatterFacts(
    court: court,
    caseNumber: caseNumber,
    petitioner: petitioner,
    respondent: respondent,
    subjectId: subjectId,
    side: side,
    stage: stage,
    benchJudgeId: benchJudgeId,
    decidingJudgeIds: [...decidingJudgeIds],
    decidingJudgeNames: [...decidingJudgeNames],
    statutes: [...statutes],
    issues: [...issues],
    relief: relief,
    summary: summary,
    counsel: [...counsel],
    source: source,
  );
}

/// Reads the facts of a matter from a Delhi High Court style judgment, order
/// or pleading with fixed rules (no AI). Anything it cannot find is left
/// empty for the user to fill in.
class FactExtractor {
  FactExtractor(this.snapshot) {
    for (var i = 0; i < snapshot.judges.length; i++) {
      final toks = snapshot.judges[i]
          .replaceFirst(RegExp(r'^(Acting )?(Chief )?Justice '), '')
          .toLowerCase()
          .split(RegExp(r'[^a-z]+'))
          .where((p) => p.length > 1)
          .toList();
      if (toks.isNotEmpty) _judgeTokens[i] = toks;
    }
    for (var i = 0; i < snapshot.counselCount; i++) {
      _counselByKey.putIfAbsent(_key(snapshot.counselName(i)), () => i);
    }
  }

  final PublicRecordsSnapshot snapshot;
  final Map<int, List<String>> _judgeTokens = {};
  final Map<String, int> _counselByKey = {};

  static String _key(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  static const _acts = {
    'arbitration and conciliation act':
        'Arbitration and Conciliation Act, 1996',
    'commercial courts act': 'Commercial Courts Act, 2015',
    'trade marks act': 'Trade Marks Act, 1999',
    'trademarks act': 'Trade Marks Act, 1999',
    'patents act': 'Patents Act, 1970',
    'copyright act': 'Copyright Act, 1957',
    'designs act': 'Designs Act, 2000',
    'code of civil procedure': 'Code of Civil Procedure, 1908',
    'cpc': 'Code of Civil Procedure, 1908',
    'specific relief act': 'Specific Relief Act, 1963',
    'indian contract act': 'Indian Contract Act, 1872',
    'contract act': 'Indian Contract Act, 1872',
    'negotiable instruments act': 'Negotiable Instruments Act, 1881',
    'insolvency and bankruptcy code': 'Insolvency and Bankruptcy Code, 2016',
    'companies act': 'Companies Act, 2013',
    'limitation act': 'Limitation Act, 1963',
    'code of criminal procedure': 'Code of Criminal Procedure, 1973',
    'crpc': 'Code of Criminal Procedure, 1973',
    'bharatiya nagarik suraksha sanhita':
        'Bharatiya Nagarik Suraksha Sanhita, 2023',
    'indian penal code': 'Indian Penal Code, 1860',
    'constitution of india': 'Constitution of India',
  };

  MatterFacts extract(String text) {
    final flat = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    final head = flat.length > 6000 ? flat.substring(0, 6000) : flat;
    final lower = flat.toLowerCase();
    final f = MatterFacts();

    // Court.
    final court = RegExp(
      r'IN\s+THE\s+HIGH\s+COURT\s+OF\s+([A-Z &]+?)(?:\s+AT\s+([A-Z ]+?))?\s*\n',
      caseSensitive: false,
    ).firstMatch(head);
    if (court != null) {
      f.court = 'High Court of ${_title(court.group(1)!.trim())}';
    } else if (lower.contains('high court of delhi') ||
        lower.contains('delhi high court')) {
      f.court = 'High Court of Delhi';
    }

    // Case number: a known case type followed by number/year, compared with
    // spaces and full stops removed ("O.M.P. (COMM.) 353/2022").
    String compact(String x) =>
        x.toUpperCase().replaceAll(RegExp(r'[\s.]'), '');
    final compactHead = compact(head);
    final types = [...snapshot.caseTypes]
      ..sort((a, b) => compact(b).length.compareTo(compact(a).length));
    String? caseType;
    for (final t in types) {
      final ct = compact(t);
      if (ct.length < 2) continue;
      final m = RegExp(
        '(?<![A-Z])${RegExp.escape(ct)}(?:NO)?(\\d{1,6})/(\\d{4})',
      ).firstMatch(compactHead);
      if (m != null) {
        caseType = t;
        f.caseNumber = '$t ${m.group(1)}/${m.group(2)}';
        break;
      }
    }
    if (caseType != null) {
      f.subjectId = subjectAreas
          .where((s) => s.matches(caseType!))
          .map((s) => s.id)
          .firstOrNull;
    }

    // Parties: the names before "..... Petitioner" and "..... Respondent".
    String? party(String role) {
      final m = RegExp(
        r'\n\s*([^\n]{3,160}?(?:\n(?:(?!\.\.\.)[^\n]){2,80}?)?)\s*\.{3,}\s*' +
            role,
        caseSensitive: false,
      ).firstMatch(head);
      return m == null
          ? null
          : _title(m.group(1)!.replaceAll('\n', ' ').trim());
    }

    f.petitioner = party(
      '(?:Petitioners?|Appellants?|Plaintiffs?|Applicants?)',
    );
    f.respondent = party('(?:Respondents?|Defendants?)');

    // Deciding bench: the CORAM block.
    final coram = RegExp(
      r'CORAM\s*:?(.{0,400}?)(?:\n\s*\d+\.|JUDGMENT|ORDER|%)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(head);
    if (coram != null) {
      final words = coram
          .group(1)!
          .toLowerCase()
          .split(RegExp(r'[^a-z]+'))
          .toSet();
      for (final e in _judgeTokens.entries) {
        final hit = e.value.where(words.contains).length;
        if (hit == e.value.length && (hit >= 2 || e.value.length == 1)) {
          f.decidingJudgeIds.add(e.key);
          f.decidingJudgeNames.add(snapshot.judges[e.key]);
        }
      }
      if (f.decidingJudgeIds.isEmpty) {
        for (final m in RegExp(
          r"JUSTICE\s+([A-Z][A-Z .]+?)(?=\s*(?:\n|HON|$))",
        ).allMatches(coram.group(1)!)) {
          f.decidingJudgeNames.add('Justice ${_title(m.group(1)!.trim())}');
        }
      }
    }

    // Counsel from the "Through:" blocks (petitioner first, then respondent).
    final through = RegExp(
      r'Through\s*:?(.{0,500}?)(?=versus|CORAM|\.{3,}|$)',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(head).toList();
    for (var i = 0; i < through.length && i < 2; i++) {
      final side = i == 0 ? RecordSide.petitioner : RecordSide.respondent;
      final seg = through[i].group(1)!.replaceAll(RegExp(r'\s+'), ' ');
      for (final m in RegExp(
        r"\b(?:Mr|Ms|Mrs|Dr)\.?\s+([A-Z][A-Za-z'\-]*(?:\s+[A-Z][A-Za-z'\-]*){0,3})",
      ).allMatches(seg)) {
        final name = m
            .group(1)!
            .replaceAll(RegExp(r'\s+(Adv|Advs|Advocate|Advocates|Sr|And)$'), '')
            .trim();
        if (name.length < 4) continue;
        f.counsel.add(
          DocumentCounsel(name, side, counselId: _counselByKey[_key(name)]),
        );
      }
    }

    // Statutes: "section 34 of the Arbitration and Conciliation Act".
    final found = <String>{};
    for (final m in RegExp(
      r'\b(?:section|sec\.?|s\.)\s*(\d+[A-Z]?)(?:\s*\(\w+\))*\s+(?:of\s+)?(?:the\s+)?([A-Za-z ]{4,60}?(?:Act|Code|Sanhita))',
      caseSensitive: false,
    ).allMatches(flat)) {
      final act = _canonical(m.group(2)!);
      if (act != null) found.add('s.${m.group(1)!.toUpperCase()} $act');
    }
    for (final e in _acts.entries) {
      if (e.key.length > 4 && lower.contains(e.key)) found.add(e.value);
    }
    f.statutes = found.toList()
      ..sort(
        (a, b) => (a.startsWith('s.') ? 0 : 1) - (b.startsWith('s.') ? 0 : 1),
      );
    if (f.subjectId == null) {
      if (found.any((s) => s.contains('Arbitration'))) {
        f.subjectId = 'arbitration';
      } else if (found.any(
        (s) => RegExp('Trade Marks|Patents|Copyright|Designs').hasMatch(s),
      )) {
        f.subjectId = 'ip';
      } else if (found.any((s) => s.contains('Commercial Courts'))) {
        f.subjectId = 'commercial';
      }
    }

    // Stage: a decided judgment or final order points to an appeal.
    final tail = lower.length > 4000
        ? lower.substring(lower.length - 4000)
        : lower;
    if (RegExp(
      r'\b(petition|appeal|suit|application)s?\b[^.]{0,60}\b(is|are|stands?)\s+(hereby\s+)?(dismissed|allowed|disposed)',
    ).hasMatch(tail)) {
      f.stage = MatterStage.appeal;
    }
    return f;
  }

  static String? _canonical(String raw) {
    final a = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final e in _acts.entries) {
      if (a.endsWith(e.key) || a.contains(e.key)) return e.value;
    }
    return null;
  }

  static String _title(String s) => s
      .replaceFirst(RegExp(r'^(versus|vs\.?)\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Merges facts read by the AI service into the facts read on the device.
/// AI values fill gaps and replace the device's rough issues; nothing the
/// user has typed is touched (merging happens before they confirm).
void mergeAiFacts(
  MatterFacts f,
  Map<String, dynamic> ai,
  PublicRecordsSnapshot snapshot,
) {
  String? str(String k) {
    final v = ai[k];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  List<String> list(String k) => [
    for (final v in (ai[k] as List? ?? const []))
      if (v is String && v.trim().isNotEmpty) v.trim(),
  ];

  f.source = str('provider') ?? 'AI';
  f.summary = str('summary') ?? f.summary;
  f.relief = str('relief_sought') ?? f.relief;
  f.court ??= str('court');
  f.caseNumber ??= str('case_number');
  if (f.petitioner == null && list('petitioners').isNotEmpty) {
    f.petitioner = list('petitioners').join(', ');
  }
  if (f.respondent == null && list('respondents').isNotEmpty) {
    f.respondent = list('respondents').join(', ');
  }
  final issues = list('issues');
  if (issues.isNotEmpty) f.issues = issues;
  for (final s in list('statutes')) {
    if (!f.statutes.contains(s)) f.statutes.add(s);
  }
  f.side ??= switch (str('client_side')) {
    'petitioner' => RecordSide.petitioner,
    'respondent' => RecordSide.respondent,
    _ => null,
  };
  if (f.stage == MatterStage.unknown) {
    f.stage = switch (str('procedural_stage')) {
      'about_to_file' => MatterStage.fresh,
      'pending_interim' => MatterStage.interim,
      'pending_final_hearing' => MatterStage.hearing,
      'decided_appeal_possible' => MatterStage.appeal,
      'execution' => MatterStage.execution,
      _ => MatterStage.unknown,
    };
  }
  if (f.subjectId == null) {
    final cat = (str('case_category') ?? '').toLowerCase();
    f.subjectId = subjectAreas
        .where(
          (s) =>
              cat.contains(s.label.toLowerCase()) ||
              s.keywords.any((k) => k.length > 3 && cat.contains(k)),
        )
        .map((s) => s.id)
        .firstOrNull;
  }
  if (f.decidingJudgeIds.isEmpty) {
    for (final name in list('deciding_judges')) {
      final toks = name
          .toLowerCase()
          .split(RegExp(r'[^a-z]+'))
          .where((p) => p.length > 1)
          .toSet();
      for (var i = 0; i < snapshot.judges.length; i++) {
        final jt = snapshot.judges[i]
            .replaceFirst(RegExp(r'^(Acting )?(Chief )?Justice '), '')
            .toLowerCase()
            .split(RegExp(r'[^a-z]+'))
            .where((p) => p.length > 1)
            .toList();
        if (jt.isNotEmpty && jt.every(toks.contains)) {
          f.decidingJudgeIds.add(i);
          f.decidingJudgeNames.add(snapshot.judges[i]);
          break;
        }
      }
    }
  }
}
