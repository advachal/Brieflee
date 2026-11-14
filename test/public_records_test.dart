import 'dart:convert';
import 'dart:io';

import 'package:brieflee/core/public_records/ask_engine.dart';
import 'package:brieflee/core/public_records/directory.dart';
import 'package:brieflee/core/public_records/matter_facts.dart';
import 'package:brieflee/core/public_records/knowledge.dart';
import 'package:brieflee/core/public_records/public_records.dart';
import 'package:flutter_test/flutter_test.dart';

PublicRecordsSnapshot _load() {
  final index = jsonDecode(
    File('assets/data/dhc_snapshot.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final parts = [
    for (final p in (index['meta']['parts'] as List).cast<String>())
      jsonDecode(File('assets/data/$p').readAsStringSync()) as List<dynamic>,
  ];
  final kFile = File('assets/data/dhc_knowledge.json');
  final knowledge = kFile.existsSync()
      ? KnowledgeLayer.fromJson(
          jsonDecode(kFile.readAsStringSync()) as Map<String, dynamic>,
        )
      : null;
  return PublicRecordsSnapshot.fromJson(index, parts, knowledge: knowledge);
}

void main() {
  late PublicRecordsSnapshot snap;
  late AskEngine engine;

  setUpAll(() {
    final sw = Stopwatch()..start();
    snap = _load();
    engine = AskEngine(snap);
    // ignore: avoid_print
    print(
      'loaded ${snap.records.length} records, ${snap.knowledge.documents} read in full, index in ${sw.elapsedMilliseconds} ms',
    );
  });

  test('snapshot holds real, attributed records with source PDFs', () {
    expect(snap.records.length, greaterThan(100000));
    expect(snap.meta.licence, 'CC BY 4.0');
    final r = snap.records.first;
    expect(r.cnr, startsWith('DLHC'));
    expect(
      snap.pdfUri(r).toString(),
      startsWith(
        'https://indian-high-court-judgments.s3.amazonaws.com/data/pdf/',
      ),
    );
    expect(snap.byId(r.id), same(r));
  });

  test('section 34 question finds arbitration decisions and ranks only well-evidenced counsel', () {
    final sw = Stopwatch()..start();
    final a = engine.ask(
      'Our client wants to set aside an arbitral award under section 34 for patent illegality',
    );
    // ignore: avoid_print
    print('ask in ${sw.elapsedMilliseconds} ms: ${a.summary}');
    expect(a.interpretation.subjects.map((s) => s.id), contains('arbitration'));
    expect(a.interpretation.subjects.map((s) => s.id), isNot(contains('ip')));
    expect(a.interpretation.sections, contains('34'));
    expect(a.interpretation.side, RecordSide.petitioner);
    expect(a.hits, isNotEmpty);
    for (final h in a.hits) {
      final t = snap.caseType(h.record).toUpperCase().replaceAll(' ', '');
      expect(
        t.startsWith('ARB') || t.startsWith('O.M.P') || t.startsWith('OMP'),
        isTrue,
        reason: t,
      );
    }
    for (final c in a.counsel) {
      expect(c.eligible, greaterThanOrEqualTo(AskEngine.minEligible));
      for (final i in [...c.favourable, ...c.unfavourable]) {
        expect(snap.outcomeOf(snap.records[i]).eligible, isTrue);
        expect(
          snap
              .counselFor(snap.records[i])
              .any((x) => x.counselId == c.counselId),
          isTrue,
        );
      }
    }
  });

  test('favourable means the counsel was on the winning side', () {
    final a = engine.ask('trademark infringement injunction');
    for (final c in a.counsel) {
      for (final i in c.favourable) {
        final r = snap.records[i];
        final side = snap
            .counselFor(r)
            .firstWhere((x) => x.counselId == c.counselId)
            .side;
        final o = snap.outcomeOf(r);
        expect(
          (o == RecordOutcome.petitioner) == (side == RecordSide.petitioner),
          isTrue,
        );
      }
    }
  });

  test('judge and case-number questions filter exactly', () {
    final j = snap.judges.indexWhere((n) => n.contains('Jyoti Singh'));
    expect(j, isNonNegative);
    final a = engine.ask('arbitration petitions before Justice Jyoti Singh');
    expect(a.interpretation.judgeIds, contains(j));
    expect(a.hits.every((h) => h.record.judgeIds.contains(j)), isTrue);

    final r = snap.records.firstWhere((r) => snap.caseType(r) == 'CS(COMM)');
    final b = engine.ask('CS(COMM) ${r.caseNo}/${r.regYear}');
    expect(b.hits.map((h) => h.record.cnr), contains(r.cnr));
  });

  test('nonsense finds nothing rather than inventing', () {
    final a = engine.ask('zzqx qqvv');
    expect(a.hits, isEmpty);
    expect(a.counsel, isEmpty);
  });

  test('an uploaded judgment becomes a query from its statutes and terms', () {
    final text = File('test/fixtures/sample_judgment.txt').readAsStringSync();
    final q = engine.documentQuery(text);
    expect(q, contains('arbitration'));
    expect(q, contains('section 34'));
    final a = engine.ask(q, side: SideChoice.respondent);
    expect(a.interpretation.side, RecordSide.respondent);
    expect(a.hits, isNotEmpty);
  });

  group('directory', () {
    late RecordsDirectory dir;
    setUpAll(() {
      final sw = Stopwatch()..start();
      dir = RecordsDirectory(snap);
      // ignore: avoid_print
      print('directory built in ${sw.elapsedMilliseconds} ms');
    });

    test('counsel stats match the records they come from', () {
      final top = dir.topCounsel(minDecided: 5);
      expect(top, isNotEmpty);
      final c = top.first;
      expect(c.isGovernment, isFalse);
      expect(c.decided, greaterThanOrEqualTo(5));
      expect(c.appearances, snap.appearanceCount(c.id));
      for (var i = 1; i < top.length; i++) {
        expect(top[i - 1].smoothedRate >= top[i].smoothedRate, isTrue);
      }
    });

    test('live search finds advocates, judges and cases as you type', () {
      final c = dir.topCounsel(minDecided: 5).first;
      final surname = c.name.split(' ').last;
      final r = dir.quickSearch(surname.substring(0, 4));
      expect(r.counsel.map((h) => h.stat.id), isNotEmpty);
      expect(dir.searchCounsel(c.name).first.id, c.id);

      final j = dir.judges.firstWhere((j) => j.decisions > 100);
      final jr = dir.quickSearch(j.name.split(' ').last);
      expect(jr.judges.map((h) => h.stat.id), contains(j.id));

      final rec = snap.records.first;
      final cr = dir.quickSearch('${rec.caseNo}/${rec.regYear}');
      expect(cr.cases.map((h) => h.record.id), contains(rec.id));

      expect(
        dir.quickSearch('arbitra').subjects.map((h) => h.subject.id),
        contains('arbitration'),
      );
    });

    test('subject counsel stats only count that subject', () {
      final ip = dir.counselFor('ip');
      final total = ip.fold<int>(0, (a, c) => a + c.appearances);
      final all = dir.counsel.fold<int>(0, (a, c) => a + c.appearances);
      expect(total, greaterThan(0));
      expect(total, lessThan(all));
    });
  });

  test('extracts case facts from an uploaded judgment', () {
    final text = File('test/fixtures/sample_judgment.txt').readAsStringSync();
    final f = FactExtractor(snap).extract(text);
    // ignore: avoid_print
    print(
      '${f.court} | ${f.caseNumber} | ${f.petitioner} v. ${f.respondent} | ${f.decidingJudgeNames} | ${f.subjectId} | ${f.stage} | ${f.statutes.take(4)} | ${f.counsel.map((c) => '${c.name}/${c.side.name}/${c.counselId}')}',
    );
    expect(f.court, 'High Court of Delhi');
    expect(f.caseNumber, contains('353/2022'));
    expect(f.petitioner, contains('New India Assurance'));
    expect(f.subjectId, 'arbitration');
    expect(f.statutes, contains('s.34 Arbitration and Conciliation Act, 1996'));
    expect(f.decidingJudgeNames.join(), contains('Sachin Datta'));
    expect(
      f.counsel
          .where((c) => c.side == RecordSide.petitioner)
          .map((c) => c.name),
      contains('Abhishek Gola'),
    );

    f.side = RecordSide.petitioner;
    f.issues = [
      'set aside arbitral award insurance policy deductible excess clause',
    ];
    f.benchJudgeId = f.decidingJudgeIds.firstOrNull;
    final a = engine.askFacts(f);
    expect(a.hits, isNotEmpty);
    for (final e in a.counsel) {
      expect(
        (e.rateComponent +
                e.relevanceComponent +
                e.sideComponent +
                e.benchComponent -
                e.score)
            .abs(),
        lessThan(1e-9),
      );
    }
  });

  test('merges the AI reading without overwriting device facts', () {
    final f = MatterFacts(source: 'device')..caseNumber = 'O.M.P. 1/2020';
    mergeAiFacts(f, {
      'provider': 'Gemini',
      'case_number': 'something else',
      'petitioners': ['A Ltd'],
      'respondents': ['B Ltd'],
      'deciding_judges': [snap.judges.first.replaceFirst('Justice ', '')],
      'procedural_stage': 'pending_interim',
      'client_side': 'respondent',
      'case_category': 'Arbitration: setting aside an award',
      'statutes': ['s.34 Arbitration and Conciliation Act, 1996'],
      'issues': ['patent illegality in the award'],
      'summary': 'A short summary.',
      'relief_sought': 'Set aside the award',
    }, snap);
    expect(f.caseNumber, 'O.M.P. 1/2020');
    expect(f.petitioner, 'A Ltd');
    expect(f.side, RecordSide.respondent);
    expect(f.stage, MatterStage.interim);
    expect(f.subjectId, 'arbitration');
    expect(f.issues, ['patent illegality in the award']);
    expect(f.source, 'Gemini');
  });

  test('ask filters: case type and bench', () {
    final plain = engine.ask('award challenged for patent illegality');
    final judge = plain.judges.firstOrNull?.judgeId;
    final a = engine.ask(
      'award challenged for patent illegality',
      subjectId: 'arbitration',
      benchJudgeId: judge,
    );
    expect(a.interpretation.subjects.map((s) => s.id), ['arbitration']);
    expect(a.benchJudgeId, judge);
  });
}
