import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/demo_providers.dart';
import '../../../core/models/models.dart';
import '../data/mock_court_repository.dart';
import '../domain/court_repository.dart';

final courtRepositoryProvider = Provider<CourtRepository>(
  (ref) => MockCourtRepository(ref.watch(demoDatasetProvider)),
);

final courtsProvider = FutureProvider<List<Court>>(
  (ref) => ref.watch(courtRepositoryProvider).listCourts(),
);

final courtProvider = FutureProvider.family<Court, String>(
  (ref, id) => ref.watch(courtRepositoryProvider).getCourt(id),
);
