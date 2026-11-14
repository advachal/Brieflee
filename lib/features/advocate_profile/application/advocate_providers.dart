import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/demo_providers.dart';
import '../../../core/models/models.dart';
import '../../judgment_viewer/application/judgment_providers.dart';
import '../data/mock_advocate_repository.dart';
import '../domain/advocate_repository.dart';

final advocateRepositoryProvider = Provider<AdvocateRepository>(
  (ref) => MockAdvocateRepository(
    ref.watch(demoDatasetProvider),
    ref.watch(judgmentRepositoryProvider),
  ),
);

final advocatesProvider = FutureProvider<List<Advocate>>(
  (ref) => ref.watch(advocateRepositoryProvider).all(),
);

final advocateProvider = FutureProvider.family<Advocate, String>(
  (ref, id) => ref.watch(advocateRepositoryProvider).get(id),
);

final advocateCasesProvider = FutureProvider.family<List<Judgment>, String>(
  (ref, id) => ref.watch(advocateRepositoryProvider).cases(id),
);
