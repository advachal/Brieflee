import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../data/mock_alert_repository.dart';
import '../domain/alert_repository.dart';

final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => MockAlertRepository(),
);

final alertEventsProvider = FutureProvider<List<AlertEvent>>(
  (ref) => ref.watch(alertRepositoryProvider).events(),
);

final alertSubscriptionsProvider = FutureProvider<List<AlertSubscription>>(
  (ref) => ref.watch(alertRepositoryProvider).subscriptions(),
);

final unreadAlertCountProvider = Provider<int>((ref) {
  final events = ref.watch(alertEventsProvider);
  return events.when(
    data: (e) => e.where((x) => !x.read).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});
