import '../../../core/api/brieflee_api.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/mock_latency.dart';
import '../../case_analysis/domain/case_analyzer.dart';
import '../domain/matter_repository.dart';

/// In-memory matters. Nothing leaves the device and nothing is persisted.
class MockMatterRepository implements MatterRepository {
  MockMatterRepository({this.analyzer = const RuleBasedDemoAnalyzer()}) {
    _seed();
  }

  final CaseAnalyzer analyzer;
  final Map<String, Matter> _matters = {};
  int _seq = 100;

  void _seed() {
    final seeded = Matter(
      id: 'm-demo-1',
      title: 'Demo: trademark interim injunction',
      createdAt: DateTime(2026, 11, 10, 11, 30),
      intakeMode: IntakeMode.caseNumber,
      description:
          'Illustrative matter. A competitor launched a snack brand '
          'with a deceptively similar mark; seeking an urgent interim injunction.',
      caseNumber: 'CS(COMM) 512/2026',
      courtId: 'dhc',
      status: MatterStatus.analyzed,
      monitored: true,
      shortlist: const ['a1', 'a2'],
    );
    _matters[seeded.id] = seeded.copyWith(analysis: analyzer.analyze(seeded));
  }

  @override
  Future<List<Matter>> list() async {
    await MockLatency.wait();
    final all = _matters.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  @override
  Future<Matter> get(String id) async {
    await MockLatency.wait(0.5);
    final m = _matters[id];
    if (m == null) throw const NotFoundFailure('This matter');
    return m;
  }

  @override
  Future<Matter> create(CreateMatterRequest r) async {
    await MockLatency.wait();
    if (r.description.trim().isEmpty &&
        (r.caseNumber == null || r.caseNumber!.trim().isEmpty) &&
        r.intakeMode != IntakeMode.upload) {
      throw const ValidationFailure(
        'Describe the matter or enter a case number to continue.',
      );
    }
    final id = 'm-${_seq++}';
    final m = Matter(
      id: id,
      title: r.title.trim().isEmpty ? 'Untitled matter' : r.title.trim(),
      createdAt: DateTime.now(),
      intakeMode: r.intakeMode,
      description: r.description.trim(),
      caseNumber: r.caseNumber?.trim().isEmpty ?? true
          ? null
          : r.caseNumber!.trim(),
      courtId: r.courtId,
      status: MatterStatus.draft,
    );
    _matters[id] = m;
    return m;
  }

  @override
  Future<MatterDocument> addDocument(
    String matterId, {
    required String fileName,
    required int sizeBytes,
    required DocumentKind kind,
  }) async {
    await MockLatency.wait(1.5);
    final m = await get(matterId);
    final doc = MatterDocument(
      id: 'doc-${_seq++}',
      fileName: fileName,
      sizeBytes: sizeBytes,
      kind: kind,
      uploadedAt: DateTime.now(),
      scanStatus: ScanStatus.clean,
    );
    _matters[matterId] = m.copyWith(documents: [...m.documents, doc]);
    return doc;
  }

  @override
  Future<Matter> removeDocument(String matterId, String documentId) async {
    final m = await get(matterId);
    final updated = m.copyWith(
      documents: m.documents.where((d) => d.id != documentId).toList(),
    );
    _matters[matterId] = updated;
    return updated;
  }

  @override
  Stream<Job> analyze(String matterId) async* {
    final jobId = 'job-analyze-${_seq++}';
    const steps = [
      'Reading the matter description',
      'Extracting text from documents (demo: file names only)',
      'Identifying court, issues, statutes and relief',
      'Checking stage of proceedings',
      'Preparing editable summary',
    ];
    for (var i = 0; i < steps.length; i++) {
      yield Job(
        id: jobId,
        status: JobStatus.running,
        progress: i / steps.length,
        step: steps[i],
      );
      await MockLatency.wait(1.4);
    }
    final m = await get(matterId);
    final analysis = analyzer.analyze(m);
    _matters[matterId] = m.copyWith(
      analysis: analysis,
      status: MatterStatus.analyzed,
    );
    yield Job(
      id: jobId,
      status: JobStatus.succeeded,
      progress: 1,
      step: 'Analysis ready',
      resultId: matterId,
    );
  }

  @override
  Future<Matter> saveAnalysis(String matterId, CaseAnalysis analysis) async {
    final m = await get(matterId);
    final updated = m.copyWith(analysis: analysis);
    _matters[matterId] = updated;
    return updated;
  }

  @override
  Future<Matter> attachRecommendation(String matterId, String recId) async {
    final m = await get(matterId);
    final updated = m.copyWith(
      recommendationIds: [...m.recommendationIds, recId],
      status: MatterStatus.matched,
    );
    _matters[matterId] = updated;
    return updated;
  }

  @override
  Future<Matter> updateShortlist(String matterId, List<String> ids) async {
    final m = await get(matterId);
    final updated = m.copyWith(shortlist: ids);
    _matters[matterId] = updated;
    return updated;
  }

  @override
  Future<Matter> setMonitored(String matterId, bool monitored) async {
    final m = await get(matterId);
    final updated = m.copyWith(monitored: monitored);
    _matters[matterId] = updated;
    return updated;
  }

  @override
  Future<void> delete(String matterId) async {
    await MockLatency.wait();
    _matters.remove(matterId);
  }

  @override
  Future<void> deleteAll() async {
    await MockLatency.wait();
    _matters.clear();
  }
}
