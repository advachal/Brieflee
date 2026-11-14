import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/demo_providers.dart';
import '../../../core/models/models.dart';
import '../data/mock_judgment_repository.dart';
import '../domain/judgment_repository.dart';

final judgmentRepositoryProvider = Provider<JudgmentRepository>(
  (ref) => MockJudgmentRepository(ref.watch(demoDatasetProvider)),
);

final judgmentProvider = FutureProvider.family<Judgment, String>(
  (ref, id) => ref.watch(judgmentRepositoryProvider).get(id),
);

/// Keyed by a comma-joined id list so the family key is a value type.
final judgmentsByIdsProvider = FutureProvider.family<List<Judgment>, String>(
  (ref, joined) => ref
      .watch(judgmentRepositoryProvider)
      .getMany(joined.isEmpty ? const [] : joined.split(',')),
);
