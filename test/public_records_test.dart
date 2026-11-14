import 'dart:convert';
import 'dart:io';

import 'package:brieflee/core/public_records/ask_engine.dart';
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
}
