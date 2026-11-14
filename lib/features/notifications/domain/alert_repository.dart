import '../../../core/api/brieflee_api.dart';
import '../../../core/models/models.dart';

/// POST /v1/alerts plus the alert feed.
abstract interface class AlertRepository {
  Future<List<AlertSubscription>> subscriptions();
  Future<AlertSubscription> create(CreateAlertRequest request);
  Future<void> setActive(String subscriptionId, bool active);
  Future<List<AlertEvent>> events();
  Future<void> markRead(String eventId);
  Future<void> markAllRead();
}
