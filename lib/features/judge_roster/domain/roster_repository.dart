import '../../../core/models/models.dart';

/// Official roster, cause list and sitting notices.
///
/// GET /v1/courts/{id}/roster and GET /v1/cases/{id}/listings.
/// A judge missing from one list is never treated as absent: the listing is
/// marked unverified instead.
abstract interface class RosterRepository {
  Future<List<Judge>> judges(String courtId);
  Future<CourtRoster?> roster(String courtId);
  Future<List<SittingNotice>> sittingNotices(String courtId);
  Future<List<CaseListing>> causeList(String courtId);

  /// Looks up the latest verified listing for a case number. Returns a
  /// listing with [ListingStatus.notFound] when no official record matches.
  Future<CaseListing> listingFor(String courtId, String caseNumber);
}
