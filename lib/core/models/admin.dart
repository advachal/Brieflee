import 'enums.dart';

enum ConnectorStatus {
  notConnected('Not connected'),
  healthy('Healthy'),
  degraded('Degraded'),
  down('Down');

  const ConnectorStatus(this.label);
  final String label;
}

class SourceHealth {
  const SourceHealth({
    required this.source,
    required this.status,
    required this.note,
    this.lastSuccess,
    this.failures24h = 0,
    this.brokenLinks = 0,
  });

  final SourceType source;
  final ConnectorStatus status;
  final String note;
  final DateTime? lastSuccess;
  final int failures24h;
  final int brokenLinks;
}

enum ReviewQueue {
  advocateDuplicates('Advocate name duplicates'),
  ambiguousRoles('Ambiguous representation roles'),
  conflictingCitations('Conflicting citations / metadata'),
  lowConfidenceOutcomes('Low-confidence outcomes'),
  rosterChanges('Roster changes to confirm'),
  brokenLinks('Broken judgment links'),
  userReports('User-reported errors');

  const ReviewQueue(this.label);
  final String label;
}

enum ReviewDecision { open, approved, rejected }

class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.queue,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.confidence,
    this.decision = ReviewDecision.open,
    this.relatedJudgmentId,
  });

  final String id;
  final ReviewQueue queue;
  final String title;
  final String detail;
  final DateTime createdAt;
  final double? confidence;
  final ReviewDecision decision;
  final String? relatedJudgmentId;

  ReviewItem decide(ReviewDecision d) => ReviewItem(
    id: id,
    queue: queue,
    title: title,
    detail: detail,
    createdAt: createdAt,
    confidence: confidence,
    decision: d,
    relatedJudgmentId: relatedJudgmentId,
  );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    required this.target,
    this.detail = '',
  });

  final String id;
  final DateTime at;
  final String actor;
  final String action;
  final String target;
  final String detail;
}
