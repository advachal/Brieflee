import 'enums.dart';

enum DocumentKind {
  petition('Petition / plaint'),
  judgment('Judgment'),
  order('Order'),
  notice('Notice'),
  submission('Written submission'),
  other('Other');

  const DocumentKind(this.label);
  final String label;
}

enum ScanStatus {
  pending('Scanning'),
  clean('Scanned'),
  rejected('Rejected');

  const ScanStatus(this.label);
  final String label;
}

class MatterDocument {
  const MatterDocument({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.kind,
    required this.uploadedAt,
    required this.scanStatus,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final DocumentKind kind;
  final DateTime uploadedAt;
  final ScanStatus scanStatus;

  factory MatterDocument.fromJson(Map<String, dynamic> j) => MatterDocument(
    id: j['id'] as String,
    fileName: j['file_name'] as String,
    sizeBytes: j['size_bytes'] as int,
    kind: enumByName(DocumentKind.values, j['kind'], DocumentKind.other),
    uploadedAt: DateTime.parse(j['uploaded_at'] as String),
    scanStatus: enumByName(
      ScanStatus.values,
      j['scan_status'],
      ScanStatus.pending,
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'file_name': fileName,
    'size_bytes': sizeBytes,
    'kind': kind.name,
    'uploaded_at': uploadedAt.toIso8601String(),
    'scan_status': scanStatus.name,
  };
}

/// Structured details extracted from the user's matter. Every field stays
/// editable; [userEdited] records which ones the user changed.
class CaseAnalysis {
  const CaseAnalysis({
    required this.courtId,
    required this.caseCategory,
    required this.legalIssues,
    required this.statutes,
    required this.reliefSought,
    required this.stage,
    required this.parties,
    required this.confidence,
    required this.analyzerLabel,
    this.caseNumber,
    this.userEdited = const {},
  });

  final String? courtId;
  final String caseCategory;
  final List<String> legalIssues;
  final List<String> statutes;
  final String reliefSought;
  final CaseStage stage;
  final String parties;
  final String? caseNumber;
  final Map<String, double> confidence;
  final String analyzerLabel;
  final Set<String> userEdited;

  CaseAnalysis copyWith({
    String? courtId,
    String? caseCategory,
    List<String>? legalIssues,
    List<String>? statutes,
    String? reliefSought,
    CaseStage? stage,
    String? parties,
    String? caseNumber,
    String? editedField,
  }) => CaseAnalysis(
    courtId: courtId ?? this.courtId,
    caseCategory: caseCategory ?? this.caseCategory,
    legalIssues: legalIssues ?? this.legalIssues,
    statutes: statutes ?? this.statutes,
    reliefSought: reliefSought ?? this.reliefSought,
    stage: stage ?? this.stage,
    parties: parties ?? this.parties,
    caseNumber: caseNumber ?? this.caseNumber,
    confidence: confidence,
    analyzerLabel: analyzerLabel,
    userEdited: editedField == null ? userEdited : {...userEdited, editedField},
  );

  factory CaseAnalysis.fromJson(Map<String, dynamic> j) => CaseAnalysis(
    courtId: j['court_id'] as String?,
    caseCategory: j['case_category'] as String,
    legalIssues: List<String>.from(j['legal_issues'] as List),
    statutes: List<String>.from(j['statutes'] as List),
    reliefSought: j['relief_sought'] as String,
    stage: enumByName(CaseStage.values, j['stage'], CaseStage.other),
    parties: j['parties'] as String,
    caseNumber: j['case_number'] as String?,
    confidence: (j['confidence'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    ),
    analyzerLabel: j['analyzer_label'] as String,
    userEdited: Set<String>.from((j['user_edited'] as List?) ?? []),
  );

  Map<String, dynamic> toJson() => {
    'court_id': courtId,
    'case_category': caseCategory,
    'legal_issues': legalIssues,
    'statutes': statutes,
    'relief_sought': reliefSought,
    'stage': stage.name,
    'parties': parties,
    'case_number': caseNumber,
    'confidence': confidence,
    'analyzer_label': analyzerLabel,
    'user_edited': userEdited.toList(),
  };
}

class Matter {
  const Matter({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.intakeMode,
    required this.description,
    required this.status,
    this.caseNumber,
    this.courtId,
    this.documents = const [],
    this.analysis,
    this.recommendationIds = const [],
    this.shortlist = const [],
    this.monitored = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final IntakeMode intakeMode;
  final String description;
  final String? caseNumber;
  final String? courtId;
  final List<MatterDocument> documents;
  final CaseAnalysis? analysis;
  final MatterStatus status;
  final List<String> recommendationIds;
  final List<String> shortlist;
  final bool monitored;

  Matter copyWith({
    String? title,
    List<MatterDocument>? documents,
    CaseAnalysis? analysis,
    MatterStatus? status,
    List<String>? recommendationIds,
    List<String>? shortlist,
    bool? monitored,
  }) => Matter(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    intakeMode: intakeMode,
    description: description,
    caseNumber: caseNumber,
    courtId: courtId,
    documents: documents ?? this.documents,
    analysis: analysis ?? this.analysis,
    status: status ?? this.status,
    recommendationIds: recommendationIds ?? this.recommendationIds,
    shortlist: shortlist ?? this.shortlist,
    monitored: monitored ?? this.monitored,
  );

  factory Matter.fromJson(Map<String, dynamic> j) => Matter(
    id: j['id'] as String,
    title: j['title'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    intakeMode: enumByName(
      IntakeMode.values,
      j['intake_mode'],
      IntakeMode.describe,
    ),
    description: j['description'] as String,
    caseNumber: j['case_number'] as String?,
    courtId: j['court_id'] as String?,
    documents: ((j['documents'] as List?) ?? [])
        .map((e) => MatterDocument.fromJson(e as Map<String, dynamic>))
        .toList(),
    analysis: j['analysis'] == null
        ? null
        : CaseAnalysis.fromJson(j['analysis'] as Map<String, dynamic>),
    status: enumByName(MatterStatus.values, j['status'], MatterStatus.draft),
    recommendationIds: List<String>.from(
      (j['recommendation_ids'] as List?) ?? [],
    ),
    shortlist: List<String>.from((j['shortlist'] as List?) ?? []),
    monitored: (j['monitored'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'intake_mode': intakeMode.name,
    'description': description,
    'case_number': caseNumber,
    'court_id': courtId,
    'documents': documents.map((d) => d.toJson()).toList(),
    'analysis': analysis?.toJson(),
    'status': status.name,
    'recommendation_ids': recommendationIds,
    'shortlist': shortlist,
    'monitored': monitored,
  };
}
