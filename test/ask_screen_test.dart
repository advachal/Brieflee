import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:brieflee/app/app.dart';
import 'package:brieflee/app/router.dart';
import 'package:brieflee/core/public_records/knowledge.dart';
import 'package:brieflee/core/public_records/public_records.dart';
import 'package:brieflee/features/ask/application/ask_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PublicRecordsSnapshot _load() {
  final index = jsonDecode(
    File('assets/data/dhc_snapshot.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return PublicRecordsSnapshot.fromJson(
    index,
    [
      for (final p in (index['meta']['parts'] as List).cast<String>())
        jsonDecode(File('assets/data/$p').readAsStringSync()) as List<dynamic>,
    ],
    knowledge: KnowledgeLayer.fromJson(
      jsonDecode(File('assets/data/dhc_knowledge.json').readAsStringSync())
          as Map<String, dynamic>,
    ),
  );
}

void main() {
  final snap = _load();

  Future<ProviderContainer> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [publicRecordsProvider.overrideWith((ref) async => snap)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const BriefleeApp()),
    );
    await tester.pumpAndSettle();
    return c;
  }

  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets(
      'ask answers a question from real records at ${size.width.toInt()}px',
      (tester) async {
        final c = await pump(tester, size);
        c
            .read(routerProvider)
            .go(Routes.ask('setting aside an arbitral award under section 34'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('How we read your question'), findsOneWidget);
        expect(find.text('Counsel who won similar matters'), findsOneWidget);
        expect(find.textContaining('Real High Court records'), findsOneWidget);
      },
    );
  }

  testWidgets('record, counsel and judge pages render', (tester) async {
    final c = await pump(tester, const Size(1300, 1000));
    final r = snap.records.firstWhere(
      (r) =>
          snap.knowledgeFor(r) != null &&
          snap.counselFor(r).isNotEmpty &&
          r.judgeIds.isNotEmpty,
    );
    for (final path in [
      Routes.record(r.id),
      Routes.recordCounsel(snap.counselFor(r).first.counselId),
      Routes.recordJudge(r.judgeIds.first),
    ]) {
      c.read(routerProvider).go(path);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
    }
    c.read(routerProvider).go(Routes.record(r.id));
    await tester.pumpAndSettle();
    expect(find.text('Open the official judgment (PDF)'), findsOneWidget);
  });
}
