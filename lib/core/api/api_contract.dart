/// Versioned REST contract between the Flutter app and the FastAPI backend
/// (blueprint section 10). Request/response shapes are documented in
/// `docs/api_contracts.md` and mirrored by the models' `toJson`/`fromJson`.
library;

enum HttpMethod { get, post, delete }

class Endpoint {
  const Endpoint(this.method, this.template, this.purpose);

  final HttpMethod method;
  final String template;
  final String purpose;

  String path([Map<String, String> params = const {}]) {
    var p = template;
    params.forEach((k, v) => p = p.replaceAll('{$k}', Uri.encodeComponent(v)));
    return p;
  }
}

abstract final class ApiContract {
  static const version = 'v1';

  static const createMatter = Endpoint(
    HttpMethod.post,
    '/v1/matters',
    'Create a legal matter',
  );
  static const uploadDocument = Endpoint(
    HttpMethod.post,
    '/v1/matters/{id}/documents',
    'Upload documents securely',
  );
  static const analyzeMatter = Endpoint(
    HttpMethod.post,
    '/v1/matters/{id}/analyze',
    'Start AI case analysis',
  );
  static const listCourts = Endpoint(
    HttpMethod.get,
    '/v1/courts',
    'Retrieve supported courts',
  );
  static const courtRoster = Endpoint(
    HttpMethod.get,
    '/v1/courts/{id}/roster',
    'Retrieve verified roster',
  );
  static const caseListings = Endpoint(
    HttpMethod.get,
    '/v1/cases/{id}/listings',
    'Retrieve case listing information',
  );
  static const startRecommendation = Endpoint(
    HttpMethod.post,
    '/v1/recommendations',
    'Start advocate matching',
  );
  static const getRecommendation = Endpoint(
    HttpMethod.get,
    '/v1/recommendations/{id}',
    'Retrieve results and explanations',
  );
  static const getAdvocate = Endpoint(
    HttpMethod.get,
    '/v1/advocates/{id}',
    'Retrieve advocate profile',
  );
  static const advocateCases = Endpoint(
    HttpMethod.get,
    '/v1/advocates/{id}/cases',
    'Retrieve verified case history',
  );
  static const getJudgment = Endpoint(
    HttpMethod.get,
    '/v1/judgments/{id}',
    'Retrieve judgment and source metadata',
  );
  static const createAlert = Endpoint(
    HttpMethod.post,
    '/v1/alerts',
    'Create monitoring subscription',
  );
  static const deleteMatter = Endpoint(
    HttpMethod.delete,
    '/v1/matters/{id}',
    'Delete matter and associated private data',
  );

  /// Long-running jobs (analysis, matching) return a job id; poll this.
  static const getJob = Endpoint(
    HttpMethod.get,
    '/v1/jobs/{id}',
    'Poll a long-running job',
  );

  static const all = [
    createMatter,
    uploadDocument,
    analyzeMatter,
    listCourts,
    courtRoster,
    caseListings,
    startRecommendation,
    getRecommendation,
    getAdvocate,
    advocateCases,
    getJudgment,
    createAlert,
    deleteMatter,
    getJob,
  ];
}
