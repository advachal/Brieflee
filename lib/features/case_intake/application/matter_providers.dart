import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../data/mock_matter_repository.dart';
import '../domain/matter_repository.dart';

final matterRepositoryProvider = Provider<MatterRepository>(
  (ref) => MockMatterRepository(),
);

final mattersProvider = FutureProvider<List<Matter>>(
  (ref) => ref.watch(matterRepositoryProvider).list(),
);

final matterProvider = FutureProvider.family<Matter, String>(
  (ref, id) => ref.watch(matterRepositoryProvider).get(id),
);

/// Call after any mutation so lists and detail views refresh.
void refreshMatters(WidgetRef ref, [String? id]) {
  ref.invalidate(mattersProvider);
  if (id != null) ref.invalidate(matterProvider(id));
}
