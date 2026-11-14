import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../domain/roster_repository.dart';

class MockRosterRepository implements RosterRepository {
  MockRosterRepository(this._data);
  final DemoDataset _data;

  @override
  Future<List<Judge>> judges(String courtId) async {
    await MockLatency.wait(0.6);
    return _data.judges.where((j) => j.courtId == courtId).toList();
  }

  @override
  Future<CourtRoster?> roster(String courtId) async {
    await MockLatency.wait(0.6);
    return _data.rosters[courtId];
  }

  @override
  Future<List<SittingNotice>> sittingNotices(String courtId) async {
    await MockLatency.wait(0.4);
    return _data.sittingNotices.where((n) => n.courtId == courtId).toList();
  }

  @override
  Future<List<CaseListing>> causeList(String courtId) async {
    await MockLatency.wait(0.4);
    return _data.listings.where((l) => l.courtId == courtId).toList();
  }

  @override
  Future<CaseListing> listingFor(String courtId, String caseNumber) async {
    await MockLatency.wait();
    String norm(String s) =>
        s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (final l in _data.listings) {
      if (l.courtId == courtId && norm(l.caseNumber) == norm(caseNumber)) {
        return l;
      }
    }
    return CaseListing(
      caseNumber: caseNumber,
      courtId: courtId,
      listingDate: DateTime.now(),
      benchJudgeIds: const [],
      courtRoom: '—',
      itemNumber: 0,
      causeListLabel: 'No matching entry in the latest demo cause list',
      status: ListingStatus.notFound,
      verification: VerificationStatus.unverified,
      lastCheckedAt: DateTime.now(),
    );
  }
}
