import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../domain/admin_repository.dart';

class MockAdminRepository implements AdminRepository {
  MockAdminRepository() {
    final t = DateTime(2026, 11, 13, 9);
    _items.addAll([
      ReviewItem(
        id: 'r1',
        queue: ReviewQueue.advocateDuplicates,
        title: '"Adv. G" and "Advocate G (Demo)" may be one person',
        detail: 'Name similarity 0.91; same chamber; overlapping matters. Merge identities?',
        createdAt: t,
        confidence: 0.91,
      ),
      ReviewItem(
        id: 'r2',
        queue: ReviewQueue.ambiguousRoles,
        title: 'Representation side unclear in J017',
        detail: 'Appearance paragraph lists counsel without the party name.',
        createdAt: t,
        confidence: 0.58,
        relatedJudgmentId: 'J017',
      ),
      ReviewItem(
        id: 'r3',
        queue: ReviewQueue.conflictingCitations,
        title: 'Order date differs between repositories',
        detail: 'Secondary repository date differs from the official record by one day.',
        createdAt: t,
        relatedJudgmentId: 'J029',
      ),
      ReviewItem(
        id: 'r4',
        queue: ReviewQueue.lowConfidenceOutcomes,
        title: 'Outcome classification at 0.46 confidence',
        detail: 'Operative paragraph lists the matter for directions; classified indeterminate.',
        createdAt: t,
        confidence: 0.46,
        relatedJudgmentId: 'J008',
      ),
      ReviewItem(
        id: 'r5',
        queue: ReviewQueue.rosterChanges,
        title: 'Roster v12: Justice Demo Golf not listed',
        detail:
            'Not present in v12. Confirm whether this is a change in assignment; '
            'status stays unverified until confirmed.',
        createdAt: t,
      ),
      ReviewItem(
        id: 'r6',
        queue: ReviewQueue.brokenLinks,
        title: '2 source links returned 404 on last check',
        detail: 'Demo links only. Recheck scheduled.',
        createdAt: t,
      ),
    ]);
    _audit.addAll([
      AuditEntry(
        id: 'au1',
        at: DateTime(2026, 11, 14, 6, 0),
        actor: 'system',
        action: 'Roster check',
        target: 'Delhi High Court',
        detail: 'No change since v12.',
      ),
      AuditEntry(
        id: 'au2',
        at: DateTime(2026, 11, 14, 6, 2),
        actor: 'system',
        action: 'Bench change detected',
        target: 'CS(COMM) 512/2026',
        detail: 'Previous assignment preserved; recommendations recalculated.',
      ),
      AuditEntry(
        id: 'au3',
        at: DateTime(2026, 11, 12, 15, 40),
        actor: 'reviewer@demo',
        action: 'Outcome corrected',
        target: 'J044',
        detail: 'Interim refused → partly allowed (correction v2).',
      ),
    ]);
  }

  final List<ReviewItem> _items = [];
  final List<AuditEntry> _audit = [];
  int _seq = 100;

  @override
  Future<List<SourceHealth>> sourceHealth() async {
    await MockLatency.wait(0.5);
    return [
      const SourceHealth(
        source: SourceType.vakilaj,
        status: ConnectorStatus.notConnected,
        note: 'Repository URL, access method and reuse permissions to be confirmed.',
      ),
      const SourceHealth(
        source: SourceType.indianKanoon,
        status: ConnectorStatus.notConnected,
        note: 'Awaiting permission review. Will be disabled gracefully if not permitted.',
      ),
      const SourceHealth(
        source: SourceType.official,
        status: ConnectorStatus.notConnected,
        note: 'Delhi High Court roster and cause-list monitoring planned for phase 4.',
      ),
      SourceHealth(
        source: SourceType.userUpload,
        status: ConnectorStatus.healthy,
        note: 'Demo index in use: fictional data only.',
        lastSuccess: DateTime(2026, 11, 14, 6),
        brokenLinks: 2,
      ),
    ];
  }

  @override
  Future<List<ReviewItem>> reviewItems() async {
    await MockLatency.wait(0.5);
    return List.unmodifiable(_items);
  }

  @override
  Future<void> decide(
    String id,
    ReviewDecision d, {
    required String actor,
  }) async {
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _items[i] = _items[i].decide(d);
    await log(
      actor,
      d == ReviewDecision.approved ? 'Review approved' : 'Review rejected',
      _items[i].title,
      'Queue: ${_items[i].queue.label}',
    );
  }

  @override
  Future<List<AuditEntry>> auditLog() async {
    await MockLatency.wait(0.4);
    return [..._audit]..sort((a, b) => b.at.compareTo(a.at));
  }

  @override
  Future<void> log(
    String actor,
    String action,
    String target, [
    String detail = '',
  ]) async {
    _audit.add(
      AuditEntry(
        id: 'au${_seq++}',
        at: DateTime.now(),
        actor: actor,
        action: action,
        target: target,
        detail: detail,
      ),
    );
  }

  @override
  Future<void> report({
    required String title,
    required String detail,
    String? judgmentId,
  }) async {
    await MockLatency.wait();
    _items.add(
      ReviewItem(
        id: 'r${_seq++}',
        queue: ReviewQueue.userReports,
        title: title,
        detail: detail,
        createdAt: DateTime.now(),
        relatedJudgmentId: judgmentId,
      ),
    );
  }
}
