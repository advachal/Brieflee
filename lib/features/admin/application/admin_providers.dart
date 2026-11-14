import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../data/mock_admin_repository.dart';
import '../domain/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => MockAdminRepository(),
);

final sourceHealthProvider = FutureProvider<List<SourceHealth>>(
  (ref) => ref.watch(adminRepositoryProvider).sourceHealth(),
);

final reviewItemsProvider = FutureProvider<List<ReviewItem>>(
  (ref) => ref.watch(adminRepositoryProvider).reviewItems(),
);

final auditLogProvider = FutureProvider<List<AuditEntry>>(
  (ref) => ref.watch(adminRepositoryProvider).auditLog(),
);
