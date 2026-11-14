import '../../../core/models/models.dart';

/// GET /v1/courts
abstract interface class CourtRepository {
  Future<List<Court>> listCourts();
  Future<Court> getCourt(String id);
}
