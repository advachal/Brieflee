import '../../../core/models/models.dart';

/// Data-quality administration. All corrections are versioned and audited.
abstract interface class AdminRepository {
  Future<List<SourceHealth>> sourceHealth();
  Future<List<ReviewItem>> reviewItems();
  Future<void> decide(
    String itemId,
    ReviewDecision decision, {
    required String actor,
  });
  Future<List<AuditEntry>> auditLog();
  Future<void> log(
    String actor,
    String action,
    String target, [
    String detail = '',
  ]);

  /// Files a user-reported error into the review queue.
  Future<void> report({
    required String title,
    required String detail,
    String? judgmentId,
  });
}
