import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/demo_providers.dart';
import '../../../core/models/models.dart';
import '../data/mock_roster_repository.dart';
import '../domain/roster_repository.dart';

final rosterRepositoryProvider = Provider<RosterRepository>(
  (ref) => MockRosterRepository(ref.watch(demoDatasetProvider)),
);

final judgesProvider = FutureProvider.family<List<Judge>, String>(
  (ref, courtId) => ref.watch(rosterRepositoryProvider).judges(courtId),
);

final rosterProvider = FutureProvider.family<CourtRoster?, String>(
  (ref, courtId) => ref.watch(rosterRepositoryProvider).roster(courtId),
);

final sittingNoticesProvider =
    FutureProvider.family<List<SittingNotice>, String>(
      (ref, courtId) =>
          ref.watch(rosterRepositoryProvider).sittingNotices(courtId),
    );

final causeListProvider = FutureProvider.family<List<CaseListing>, String>(
  (ref, courtId) => ref.watch(rosterRepositoryProvider).causeList(courtId),
);

typedef ListingQuery = ({String courtId, String caseNumber});

final caseListingProvider = FutureProvider.family<CaseListing, ListingQuery>(
  (ref, q) =>
      ref.watch(rosterRepositoryProvider).listingFor(q.courtId, q.caseNumber),
);

/// Synchronous judge-name lookup for display.
final judgeNameProvider = Provider.family<String, String>(
  (ref, id) => ref.watch(demoDatasetProvider).judgeName(id),
);
