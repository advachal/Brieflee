import 'dart:ui' show Size;

import 'package:brieflee/app/app.dart';
import 'package:brieflee/app/router.dart';
import 'package:brieflee/shared/utilities/mock_latency.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const BriefleeApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => MockLatency.base = Duration.zero);

  testWidgets('home shows the search and the demo-data notice', (tester) async {
    await _pump(tester, const Size(1400, 1000));
    expect(find.textContaining('not guesswork'), findsOneWidget);
    expect(find.textContaining('Illustrative demo data'), findsOneWidget);
  });

  testWidgets('desktop results use three panels', (tester) async {
    final c = await _pump(tester, const Size(1600, 1000));
    c.read(routerProvider).go(Routes.results('rec-demo-1'));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsWidgets);
    expect(find.text('Recommended advocates'), findsOneWidget);
    expect(find.textContaining('Why Advocate'), findsOneWidget);
  });

  testWidgets('phone results use expandable cards and a filter sheet', (
    tester,
  ) async {
    final c = await _pump(tester, const Size(400, 860));
    c.read(routerProvider).go(Routes.results('rec-demo-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Why this advocate?'), findsWidgets);
    await tester.tap(find.text('Filters').first);
    await tester.pumpAndSettle();
    expect(find.text('Show results'), findsOneWidget);
  });

  testWidgets('every main route renders without errors', (tester) async {
    final c = await _pump(tester, const Size(1300, 1000));
    for (final path in [
      Routes.newMatter,
      Routes.analysis('m-demo-1'),
      Routes.courts,
      Routes.court('dhc'),
      Routes.judges(),
      Routes.advocate('a1', rec: 'rec-demo-1'),
      Routes.compare(rec: 'rec-demo-1', ids: ['a1', 'a2']),
      Routes.judgment('J001'),
      Routes.saved,
      Routes.alerts,
      Routes.settings,
      Routes.login,
    ]) {
      c.read(routerProvider).go(path);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
    }
  });
}
