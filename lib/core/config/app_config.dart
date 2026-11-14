/// How the app is sourcing its data.
enum DataMode {
  /// Illustrative, fictional data bundled with the app. Never real advocates.
  demo,

  /// Live backend at [AppConfig.apiBaseUrl]. Not enabled in this milestone.
  live,
}

/// Static configuration for this build.
///
/// Live judgment sources stay disabled until repository access, terms and
/// reuse permissions are confirmed (blueprint sections 2 and 12).
abstract final class AppConfig {
  static const dataMode = DataMode.demo;
  static const apiBaseUrl = String.fromEnvironment(
    'BRIEFLEE_API_BASE_URL',
    defaultValue: 'https://api.example.invalid',
  );
  static const pilotCourtId = 'dhc';

  static const vakilajEnabled = false;
  static const indianKanoonEnabled = false;
  static const officialCourtSourcesEnabled = false;

  /// Real public records (Delhi High Court, eCourts metadata and judgment
  /// text via AWS Open Data, CC BY 4.0) power Ask and the Records pages.
  static const publicRecordsEnabled = true;

  /// Optional knowledge service (server/) for full-text RAG and grounded
  /// generated answers. Empty means the app answers on-device only.
  static const knowledgeServiceUrl = String.fromEnvironment(
    'BRIEFLEE_KNOWLEDGE_URL',
    defaultValue: '',
  );

  static const publicRecordsNotice =
      'Real High Court records (eCourts via AWS Open Data, CC BY 4.0). '
      'Counsel and outcomes are read from the judgments and may be incomplete; verify before relying on them.';

  static const demoDisclaimer =
      'Illustrative demo data. All advocates, judges, cases and statistics '
      'shown are fictional and must not be relied on.';
}
