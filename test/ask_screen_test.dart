import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:brieflee/app/app.dart';
import 'package:brieflee/app/router.dart';
import 'package:brieflee/core/public_records/knowledge.dart';
import 'package:brieflee/core/public_records/matter_facts.dart';
import 'package:brieflee/core/public_records/public_records.dart';
import 'package:brieflee/features/ask/application/ask_providers.dart';
import 'package:brieflee/features/ask/presentation/matter_facts_panel.dart';
import 'package:material_ui/material_ui.dart';
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

  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('facts panel renders and confirms at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = FactExtractor(
        snap,
      ).extract(File('test/fixtures/sample_judgment.txt').readAsStringSync());
      MatterFacts? got;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatterFactsPanel(
                facts: f,
                snapshot: snap,
                onConfirm: (v) => got = v,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Check the facts of your matter'), findsOneWidget);
      await tester.tap(find.text('Petitioner'));
      await tester.pump();
      final btn = find.text('Find matching advocates');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      expect(got?.side, RecordSide.petitioner);
      expect(got?.caseNumber, contains('353/2022'));
    });
  }

  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('why this advocate and compare at ${size.width.toInt()}px', (
      tester,
    ) async {
      final c = await pump(tester, size);
      c
          .read(routerProvider)
          .go(Routes.ask('set aside arbitral award section 34'));
      await tester.pumpAndSettle();
      void press(Finder f) => tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(of: f, matching: find.bySubtype<ButtonStyleButton>())
                .first,
          )
          .onPressed!();
      press(find.text('Why this advocate').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Outcomes'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        tester.widget<Checkbox>(find.byType(Checkbox).at(i)).onChanged!(true);
        await tester.pumpAndSettle();
      }
      press(find.text('Compare'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Compare advocates'), findsOneWidget);
      expect(find.text('Evidence confidence'), findsOneWidget);
    });
  }
}
