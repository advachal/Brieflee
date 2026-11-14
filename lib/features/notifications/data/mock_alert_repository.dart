import '../../../core/api/brieflee_api.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../domain/alert_repository.dart';

class MockAlertRepository implements AlertRepository {
  MockAlertRepository() {
    _subs.add(
      AlertSubscription(
        id: 'sub-1',
        label: 'Demo: trademark interim injunction',
        kinds: {
          AlertKind.benchChange,
          AlertKind.listingChange,
          AlertKind.newJudgment,
        },
        createdAt: DateTime(2026, 11, 10, 11, 50),
        active: true,
        matterId: 'm-demo-1',
      ),
    );
    _subs.add(
      AlertSubscription(
        id: 'sub-2',
        label: 'Delhi High Court roster',
        kinds: {AlertKind.rosterChange},
        createdAt: DateTime(2026, 9, 2),
        active: true,
        courtId: 'dhc',
      ),
    );
    _events.addAll([
      AlertEvent(
        id: 'ev-1',
        kind: AlertKind.benchChange,
        title: 'Bench changed for CS(COMM) 512/2026',
        body:
            'The demo advance cause list for 18 Nov 2026 lists the matter '
            'before a different bench. The previous assignment is kept in '
            'history and recommendations were recalculated.',
        at: DateTime(2026, 11, 14, 6, 2),
        verification: VerificationStatus.verified,
        matterId: 'm-demo-1',
        previousValue: 'Justice Demo Charlie (Court 21)',
        currentValue: 'Justice Demo Alpha (Court 21)',
      ),
      AlertEvent(
        id: 'ev-2',
        kind: AlertKind.recommendationUpdated,
        title: 'Recommendations updated after bench change',
        body:
            'Judge-specific experience now reflects the newly listed bench. '
            'Methodology version unchanged.',
        at: DateTime(2026, 11, 14, 6, 3),
        verification: VerificationStatus.verified,
        matterId: 'm-demo-1',
      ),
      AlertEvent(
        id: 'ev-3',
        kind: AlertKind.rosterChange,
        title: 'Delhi High Court roster v12 published',
        body:
            'Five bench assignments changed from v11. One judge is not '
            'listed in v12; status marked unverified, not absent.',
        at: DateTime(2026, 10, 6, 7, 0),
        verification: VerificationStatus.verified,
        previousValue: 'Roster v11 (effective 1 Jul 2026)',
        currentValue: 'Roster v12 (effective 6 Oct 2026)',
        read: true,
      ),
      AlertEvent(
        id: 'ev-4',
        kind: AlertKind.newJudgment,
        title: 'New comparable judgment indexed',
        body:
            'A fictional trademark interim-injunction judgment involving a '
            'shortlisted advocate was added to the demo index.',
        at: DateTime(2026, 11, 12, 18, 20),
        verification: VerificationStatus.pendingReview,
        matterId: 'm-demo-1',
      ),
    ]);
  }

  final List<AlertSubscription> _subs = [];
  final List<AlertEvent> _events = [];
  int _seq = 10;

  @override
  Future<List<AlertSubscription>> subscriptions() async {
    await MockLatency.wait(0.5);
    return List.unmodifiable(_subs);
  }

  @override
  Future<AlertSubscription> create(CreateAlertRequest r) async {
    await MockLatency.wait();
    final s = AlertSubscription(
      id: 'sub-${_seq++}',
      label: r.label,
      kinds: r.kinds,
      createdAt: DateTime.now(),
      active: true,
      matterId: r.matterId,
      courtId: r.courtId,
    );
    _subs.add(s);
    return s;
  }

  @override
  Future<void> setActive(String id, bool active) async {
    final i = _subs.indexWhere((s) => s.id == id);
    if (i >= 0) _subs[i] = _subs[i].copyWith(active: active);
  }

  @override
  Future<List<AlertEvent>> events() async {
    await MockLatency.wait(0.5);
    return [..._events]..sort((a, b) => b.at.compareTo(a.at));
  }

  @override
  Future<void> markRead(String id) async {
    final i = _events.indexWhere((e) => e.id == id);
    if (i >= 0) _events[i] = _events[i].markRead();
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _events.length; i++) {
      _events[i] = _events[i].markRead();
    }
  }
}
