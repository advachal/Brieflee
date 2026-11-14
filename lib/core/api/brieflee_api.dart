import '../errors/app_failure.dart';
import '../models/models.dart';
import 'api_contract.dart';

/// Minimal transport so the API client stays independent of any HTTP
/// package. A production build plugs in an authenticated HTTPS transport
/// (TLS, bearer token from Firebase Auth / OIDC, retries, tracing headers).
abstract interface class ApiTransport {
  Future<Object?> send(
    HttpMethod method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  });

  /// Multipart upload. Bytes are streamed and never logged.
  Future<Object?> upload(
    String path, {
    required String fileName,
    required List<int> bytes,
    required Map<String, String> fields,
  });
}

// ---- Request DTOs ----------------------------------------------------------

class CreateMatterRequest {
  const CreateMatterRequest({
    required this.title,
    required this.intakeMode,
    required this.description,
    this.caseNumber,
    this.courtId,
  });

  final String title;
  final IntakeMode intakeMode;
  final String description;
  final String? caseNumber;
  final String? courtId;

  Map<String, dynamic> toJson() => {
    'title': title,
    'intake_mode': intakeMode.name,
    'description': description,
    'case_number': caseNumber,
    'court_id': courtId,
  };
}

class StartRecommendationRequest {
  const StartRecommendationRequest({
    required this.matterId,
    required this.analysis,
    required this.filters,
    required this.methodologyVersion,
  });

  final String matterId;
  final CaseAnalysis analysis;
  final SearchFilters filters;
  final String methodologyVersion;

  Map<String, dynamic> toJson() => {
    'matter_id': matterId,
    'analysis': analysis.toJson(),
    'filters': filters.toJson(),
    'methodology_version': methodologyVersion,
  };
}

class CreateAlertRequest {
  const CreateAlertRequest({
    required this.label,
    required this.kinds,
    this.matterId,
    this.courtId,
  });

  final String label;
  final Set<AlertKind> kinds;
  final String? matterId;
  final String? courtId;

  Map<String, dynamic> toJson() => {
    'label': label,
    'kinds': kinds.map((k) => k.name).toList(),
    'matter_id': matterId,
    'court_id': courtId,
  };
}

// ---- Client ----------------------------------------------------------------

/// Typed client for every endpoint in [ApiContract]. Not wired into the
/// running app in this milestone: the app uses mock repositories instead.
class BriefleeApi {
  const BriefleeApi(this._t);
  final ApiTransport _t;

  Map<String, dynamic> _obj(Object? o) {
    if (o is Map<String, dynamic>) return o;
    throw const NetworkFailure('Unexpected response from server.');
  }

  List<Map<String, dynamic>> _list(Object? o) {
    if (o is List) return o.cast<Map<String, dynamic>>();
    throw const NetworkFailure('Unexpected response from server.');
  }

  Future<Matter> createMatter(CreateMatterRequest r) async => Matter.fromJson(
    _obj(
      await _t.send(
        HttpMethod.post,
        ApiContract.createMatter.path(),
        body: r.toJson(),
      ),
    ),
  );

  Future<MatterDocument> uploadDocument(
    String matterId, {
    required String fileName,
    required List<int> bytes,
    required DocumentKind kind,
  }) async => MatterDocument.fromJson(
    _obj(
      await _t.upload(
        ApiContract.uploadDocument.path({'id': matterId}),
        fileName: fileName,
        bytes: bytes,
        fields: {'kind': kind.name},
      ),
    ),
  );

  Future<Job> analyzeMatter(String matterId) async => Job.fromJson(
    _obj(
      await _t.send(
        HttpMethod.post,
        ApiContract.analyzeMatter.path({'id': matterId}),
      ),
    ),
  );

  Future<List<Court>> listCourts() async =>
      _list(await _t.send(HttpMethod.get, ApiContract.listCourts.path()))
          .map(Court.fromJson)
          .toList();

  Future<RosterVersion> courtRoster(String courtId) async =>
      RosterVersion.fromJson(
        _obj(
          await _t.send(
            HttpMethod.get,
            ApiContract.courtRoster.path({'id': courtId}),
          ),
        ),
      );

  Future<List<CaseListing>> caseListings(String caseId) async => _list(
    await _t.send(
      HttpMethod.get,
      ApiContract.caseListings.path({'id': caseId}),
    ),
  ).map(CaseListing.fromJson).toList();

  Future<Job> startRecommendation(StartRecommendationRequest r) async =>
      Job.fromJson(
        _obj(
          await _t.send(
            HttpMethod.post,
            ApiContract.startRecommendation.path(),
            body: r.toJson(),
          ),
        ),
      );

  /// Returns the raw payload; the recommendation view model is assembled by
  /// the repository so it can resolve advocates and judgments it references.
  Future<Map<String, dynamic>> getRecommendation(String id) async => _obj(
    await _t.send(
      HttpMethod.get,
      ApiContract.getRecommendation.path({'id': id}),
    ),
  );

  Future<Advocate> getAdvocate(String id) async => Advocate.fromJson(
    _obj(
      await _t.send(HttpMethod.get, ApiContract.getAdvocate.path({'id': id})),
    ),
  );

  Future<List<Judgment>> advocateCases(String id) async => _list(
    await _t.send(HttpMethod.get, ApiContract.advocateCases.path({'id': id})),
  ).map(Judgment.fromJson).toList();

  Future<Judgment> getJudgment(String id) async => Judgment.fromJson(
    _obj(
      await _t.send(HttpMethod.get, ApiContract.getJudgment.path({'id': id})),
    ),
  );

  Future<AlertSubscription> createAlert(CreateAlertRequest r) async =>
      AlertSubscription.fromJson(
        _obj(
          await _t.send(
            HttpMethod.post,
            ApiContract.createAlert.path(),
            body: r.toJson(),
          ),
        ),
      );

  Future<void> deleteMatter(String id) =>
      _t.send(HttpMethod.delete, ApiContract.deleteMatter.path({'id': id}));

  Future<Job> getJob(String id) async => Job.fromJson(
    _obj(await _t.send(HttpMethod.get, ApiContract.getJob.path({'id': id}))),
  );
}
