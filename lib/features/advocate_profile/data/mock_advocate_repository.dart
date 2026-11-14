import '../../../core/errors/app_failure.dart';
import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../../judgment_viewer/domain/judgment_repository.dart';
import '../domain/advocate_repository.dart';

class MockAdvocateRepository implements AdvocateRepository {
  MockAdvocateRepository(this._data, this._judgments);
  final DemoDataset _data;
  final JudgmentRepository _judgments;

  @override
  Future<List<Advocate>> all() async {
    await MockLatency.wait(0.4);
    return _data.advocates;
  }

  @override
  Future<Advocate> get(String id) async {
    await MockLatency.wait(0.5);
    final a = _data.advocate(id);
    if (a == null) throw const NotFoundFailure('This advocate');
    return a;
  }

  @override
  Future<List<Judgment>> cases(String id) async {
    final all = await _judgments.all();
    return all.where((j) => j.appearanceOf(id) != null).toList();
  }

  @override
  int mentionOnlyCount(String id) => _data.mentionOnlyCounts[id] ?? 0;
}
