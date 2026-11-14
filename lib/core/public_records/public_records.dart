/// Real, public court records (phase 2 pilot: Delhi High Court).
///
/// These types hold *only* what the source publishes. Nothing is inferred
/// beyond simple parsing, and every record keeps a link to its source PDF.
library;

import 'knowledge.dart';

/// Where a snapshot came from and how it may be reused.
class RecordsSourceMeta {
  const RecordsSourceMeta({
    required this.courtId,
    required this.court,
    required this.source,
    required this.sourceUrl,
    required this.licence,
    required this.attribution,
    required this.years,
    required this.built,
    required this.count,
    required this.pdfBase,
    required this.pdfPath,
    required this.pdfDefault,
    required this.parts,
  });

  final String courtId;
  final String court;
  final String source;
  final String sourceUrl;
  final String licence;
  final String attribution;
  final List<String> years;
  final String built;
  final int count;
  final String pdfBase;
  final String pdfPath;
  final String pdfDefault;
  final List<String> parts;

  factory RecordsSourceMeta.fromJson(Map<String, dynamic> j) =>
      RecordsSourceMeta(
        courtId: j['court_id'] as String,
        court: j['court'] as String,
        source: j['source'] as String,
        sourceUrl: j['source_url'] as String,
        licence: j['licence'] as String,
        attribution: j['attribution'] as String,
        years: (j['years'] as List).cast<String>(),
        built: j['built'] as String,
        count: j['count'] as int,
        pdfBase: j['pdf_base'] as String,
        pdfPath: j['pdf_path'] as String,
        pdfDefault: j['pdf_default'] as String,
        parts: (j['parts'] as List).cast<String>(),
      );

  String get yearRange => years.isEmpty
      ? ''
      : (years.length == 1 ? years.first : '${years.first} to ${years.last}');
}

/// Which side a counsel appeared for, as written in the judgment header.
enum RecordSide {
  petitioner('Petitioner / appellant side'),
  respondent('Respondent side');

  const RecordSide(this.label);
  final String label;
}

/// How a counsel was described in the header.
enum CounselRole {
  advocate('Advocate'),
  senior('Senior Advocate'),
  government('Government / prosecution counsel');

  const CounselRole(this.label);
  final String label;
}

enum RecordDocType {
  judgment('Judgment'),
  order('Order'),
  unknown('Order or judgment');

  const RecordDocType(this.label);
  final String label;
}

class CounselAppearance {
  const CounselAppearance(this.counselId, this.side, this.role);
  final int counselId;
  final RecordSide side;
  final CounselRole role;
}

/// One decision (order or judgment) as published by the court.
class CourtRecord {
  const CourtRecord({
    required this.index,
    required this.cnr,
    required this.caseTypeId,
    required this.caseNo,
    required this.regYear,
    required this.petitioner,
    required this.respondent,
    required this.date,
    required this.judgeIds,
    required this.counsel,
    required this.pdfFile,
    required this.docType,
    required this.srcYear,
    this.courtIndex = 0,
  });

  final int index;
  final String cnr;
  final int caseTypeId;
  final String caseNo;
  final int regYear;
  final String petitioner;
  final String respondent;
  final DateTime date;
  final List<int> judgeIds;
  final List<CounselAppearance> counsel;
  final String pdfFile;
  final RecordDocType docType;
  final int srcYear;

  /// Index into [PublicRecordsSnapshot.courts].
  final int courtIndex;

  /// Stable route id: CNR plus decision date (one CNR can have many orders).
  String get id => '${cnr}_${_iso(date)}';

  String get title => '$petitioner v. $respondent';
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The loaded snapshot with lookup indexes.
class PublicRecordsSnapshot {
  PublicRecordsSnapshot({
    required this.courts,
    required this.caseTypes,
    required this.judges,
    required this.counselNames,
    required this.records,
    KnowledgeLayer? knowledge,
  }) : knowledge = knowledge ?? KnowledgeLayer.empty {
    for (final r in records) {
      _byId[r.id] = r;
      for (final j in r.judgeIds) {
        (_byJudge[j] ??= []).add(r.index);
      }
      for (final c in counselFor(r)) {
        final list = _byCounsel[c.counselId] ??= [];
        if (list.isEmpty || list.last != r.index) list.add(r.index);
      }
    }
  }

  final KnowledgeLayer knowledge;

  KnowledgeEntry? knowledgeFor(CourtRecord r) => knowledge.entries[r.id];

  RecordOutcome outcomeOf(CourtRecord r) =>
      knowledge.entries[r.id]?.outcome ?? RecordOutcome.unknown;

  /// Counsel from the full judgment header when its text has been read,
  /// otherwise from the short metadata excerpt.
  List<CounselAppearance> counselFor(CourtRecord r) {
    final k = knowledge.entries[r.id];
    if (k == null || k.counsel.isEmpty) return r.counsel;
    return [
      for (final c in k.counsel)
        CounselAppearance(
          c[0] as int,
          c[1] == 'p' ? RecordSide.petitioner : RecordSide.respondent,
          switch (c[2]) {
            'sr' => CounselRole.senior,
            'gov' => CounselRole.government,
            _ => CounselRole.advocate,
          },
        ),
    ];
  }

  String counselName(int id) {
    if (id < counselNames.length) return counselNames[id];
    final i = id - knowledge.extraCounselStart;
    return (i >= 0 && i < knowledge.extraCounsel.length)
        ? knowledge.extraCounsel[i]
        : 'Unknown';
  }

  int get counselCount => counselNames.length + knowledge.extraCounsel.length;

  /// One entry per court snapshot loaded.
  final List<RecordsSourceMeta> courts;

  /// The first court; used for attribution text shared by all courts.
  RecordsSourceMeta get meta => courts.first;

  RecordsSourceMeta courtOf(CourtRecord r) => courts[r.courtIndex];

  List<String> get years =>
      {for (final c in courts) ...c.years}.toList()..sort();

  String get yearRange {
    final y = years;
    return y.isEmpty
        ? ''
        : (y.length == 1 ? y.first : '${y.first} to ${y.last}');
  }

  String get courtNames => courts.map((c) => c.court).join(' and ');

  final List<String> caseTypes;
  final List<String> judges;
  final List<String> counselNames;

  /// Newest first.
  final List<CourtRecord> records;

  final Map<String, CourtRecord> _byId = {};
  final Map<int, List<int>> _byJudge = {};
  final Map<int, List<int>> _byCounsel = {};

  CourtRecord? byId(String id) => _byId[id];

  List<CourtRecord> recordsForJudge(int judgeId) => [
    for (final i in _byJudge[judgeId] ?? const <int>[]) records[i],
  ];

  List<CourtRecord> recordsForCounsel(int counselId) => [
    for (final i in _byCounsel[counselId] ?? const <int>[]) records[i],
  ];

  int appearanceCount(int counselId) => _byCounsel[counselId]?.length ?? 0;

  int decisionCount(int judgeId) => _byJudge[judgeId]?.length ?? 0;

  String caseType(CourtRecord r) => caseTypes[r.caseTypeId];

  String caseNumber(CourtRecord r) =>
      '${caseTypes[r.caseTypeId]} ${r.caseNo}/${r.regYear}';

  Uri pdfUri(CourtRecord r) {
    final meta = courtOf(r);
    final file = r.pdfFile.isNotEmpty
        ? r.pdfFile
        : meta.pdfDefault
              .replaceAll('{cnr}', r.cnr)
              .replaceAll('{date}', _iso(r.date));
    final path = meta.pdfPath
        .replaceAll('{src_year}', '${r.srcYear}')
        .replaceAll('{file}', file);
    return Uri.parse('${meta.pdfBase}$path');
  }

  /// Parses one court's bundled JSON (index + yearly parts).
  static PublicRecordsSnapshot fromJson(
    Map<String, dynamic> index,
    List<List<dynamic>> parts, {
    KnowledgeLayer? knowledge,
  }) => merge([CourtSnapshotJson(index, parts, knowledge)]);

  /// Merges several courts into one snapshot. Judge, case-type and counsel
  /// ids are offset per court, so the same name in two courts stays two
  /// entries (names are not identities).
  static PublicRecordsSnapshot merge(List<CourtSnapshotJson> inputs) {
    final courts = <RecordsSourceMeta>[];
    final caseTypes = <String>[];
    final judges = <String>[];
    final counselNames = <String>[];
    final rows = <(int, int, int, int, List<dynamic>)>[];
    final entries = <String, KnowledgeEntry>{};
    final outcomeCounts = <String, int>{};

    for (var ci = 0; ci < inputs.length; ci++) {
      final input = inputs[ci];
      courts.add(
        RecordsSourceMeta.fromJson(input.index['meta'] as Map<String, dynamic>),
      );
      final typeOff = caseTypes.length;
      final judgeOff = judges.length;
      final counselOff = counselNames.length;
      caseTypes.addAll((input.index['case_types'] as List).cast<String>());
      judges.addAll((input.index['judges'] as List).cast<String>());
      final base = (input.index['counsel'] as List).cast<String>();
      counselNames.addAll(base);
      final k = input.knowledge;
      if (k != null) {
        counselNames.addAll(k.extraCounsel);
        int remap(int id) => id < base.length
            ? id + counselOff
            : counselOff + base.length + (id - k.extraCounselStart);
        for (final e in k.entries.entries) {
          final v = e.value;
          entries[e.key] = KnowledgeEntry(
            outcome: v.outcome,
            evidence: v.evidence,
            terms: v.terms,
            statutes: v.statutes,
            counsel: [
              for (final c in v.counsel) [remap(c[0] as int), c[1], c[2]],
            ],
            pages: v.pages,
          );
        }
        k.outcomeCounts.forEach(
          (key, n) => outcomeCounts[key] = (outcomeCounts[key] ?? 0) + n,
        );
      }
      for (final p in input.parts) {
        for (final r in p.cast<List<dynamic>>()) {
          rows.add((ci, typeOff, judgeOff, counselOff, r));
        }
      }
    }
    rows.sort((a, b) => (b.$5[6] as String).compareTo(a.$5[6] as String));
    final records = <CourtRecord>[];
    for (var i = 0; i < rows.length; i++) {
      final (ci, typeOff, judgeOff, counselOff, r) = rows[i];
      records.add(
        CourtRecord(
          index: i,
          courtIndex: ci,
          cnr: r[0] as String,
          caseTypeId: (r[1] as int) + typeOff,
          caseNo: r[2] as String,
          regYear: r[3] as int,
          petitioner: r[4] as String,
          respondent: r[5] as String,
          date: DateTime.parse(r[6] as String),
          judgeIds: [for (final j in r[7] as List) (j as int) + judgeOff],
          counsel: [
            for (final c in r[8] as List)
              CounselAppearance(
                ((c as List)[0] as int) + counselOff,
                c[1] == 'p' ? RecordSide.petitioner : RecordSide.respondent,
                switch (c[2]) {
                  'sr' => CounselRole.senior,
                  'gov' => CounselRole.government,
                  _ => CounselRole.advocate,
                },
              ),
          ],
          pdfFile: r[9] as String,
          docType: switch (r[10]) {
            'j' => RecordDocType.judgment,
            'o' => RecordDocType.order,
            _ => RecordDocType.unknown,
          },
          srcYear: r[11] as int,
        ),
      );
    }
    return PublicRecordsSnapshot(
      courts: courts,
      caseTypes: caseTypes,
      judges: judges,
      counselNames: counselNames,
      records: records,
      knowledge: KnowledgeLayer(
        entries: entries,
        extraCounselStart: 1 << 30,
        extraCounsel: const [],
        outcomeCounts: outcomeCounts,
      ),
    );
  }
}

/// Raw JSON for one court, as bundled in assets/data.
class CourtSnapshotJson {
  const CourtSnapshotJson(this.index, this.parts, [this.knowledge]);
  final Map<String, dynamic> index;
  final List<List<dynamic>> parts;
  final KnowledgeLayer? knowledge;
}
