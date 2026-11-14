import '../../../core/errors/app_failure.dart';
import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../domain/court_repository.dart';

class MockCourtRepository implements CourtRepository {
  MockCourtRepository(this._data);
  final DemoDataset _data;

  @override
  Future<List<Court>> listCourts() async {
    await MockLatency.wait();
    return _data.courts;
  }

  @override
  Future<Court> getCourt(String id) async {
    await MockLatency.wait(0.5);
    return _data.courts.firstWhere(
      (c) => c.id == id,
      orElse: () => throw const NotFoundFailure('This court'),
    );
  }
}
