import 'advocate.dart';
import 'enums.dart';

/// Where a judgment was found. A judgment found in several repositories keeps
/// one reference per repository but counts as one case.
class JudgmentSourceRef {
  const JudgmentSourceRef({
    required this.type,
    required this.retrievedAt,
    required this.documentVersion,
    required this.verification,
    this.url,
    this.externalId,
  });

  final SourceType type;
  final String? url;
  final String? externalId;
  final DateTime retrievedAt;
  final String documentVersion;
  final VerificationStatus verification;

  factory JudgmentSourceRef.fromJson(Map<String, dynamic> j) =>
      JudgmentSourceRef(
        type: enumByName(SourceType.values, j['type'], SourceType.official),
        url: j['url'] as String?,
        externalId: j['external_id'] as String?,
        retrievedAt: DateTime.parse(j['retrieved_at'] as String),
        documentVersion: j['document_version'] as String,
        verification: enumByName(
          VerificationStatus.values,
          j['verification'],
          VerificationStatus.unverified,
        ),
      );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'url': url,
    'external_id': externalId,
    'retrieved_at': retrievedAt.toIso8601String(),
    'document_version': documentVersion,
    'verification': verification.name,
  };
}

/// A passage of judgment text that supports a classification.
class Passage {
  const Passage({
    required this.id,
    required this.paragraph,
    required this.text,
    required this.supports,
  });

  final String id;
  final String paragraph;
  final String text;
  final String supports;

  factory Passage.fromJson(Map<String, dynamic> j) => Passage(
    id: j['id'] as String,
    paragraph: j['paragraph'] as String,
    text: j['text'] as String,
    supports: j['supports'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'paragraph': paragraph,
    'text': text,
    'supports': supports,
  };
}

class Judgment {
  const Judgment({
    required this.id,
    required this.title,
    required this.citation,
    required this.caseNumber,
    required this.courtId,
    required this.benchJudgeIds,
    required this.date,
    required this.category,
    required this.statutes,
    required this.stage,
    required this.disposition,
    required this.dispositionConfidence,
    required this.reviewStatus,
    required this.appearances,
    required this.sources,
    required this.passages,
    required this.summary,
    this.conflictNote,
  });

  final String id;
  final String title;
  final String citation;
  final String caseNumber;
  final String courtId;
  final List<String> benchJudgeIds;
  final DateTime date;
  final String category;
  final List<String> statutes;
  final CaseStage stage;
  final CaseDisposition disposition;
  final double dispositionConfidence;
  final ReviewStatus reviewStatus;
  final List<Appearance> appearances;
  final List<JudgmentSourceRef> sources;
  final List<Passage> passages;
  final String summary;

  /// Set when repositories disagree with the official record.
  final String? conflictNote;

  bool get hasConflict => conflictNote != null;

  Appearance? appearanceOf(String advocateId) {
    for (final a in appearances) {
      if (a.advocateId == advocateId) return a;
    }
    return null;
  }

  PartyOutcome outcomeFor(String advocateId) {
    final a = appearanceOf(advocateId);
    if (a == null) return PartyOutcome.excluded;
    return disposition.outcomeFor(a.side);
  }

  factory Judgment.fromJson(Map<String, dynamic> j) => Judgment(
    id: j['id'] as String,
    title: j['title'] as String,
    citation: j['citation'] as String,
    caseNumber: j['case_number'] as String,
    courtId: j['court_id'] as String,
    benchJudgeIds: List<String>.from(j['bench_judge_ids'] as List),
    date: DateTime.parse(j['date'] as String),
    category: j['category'] as String,
    statutes: List<String>.from(j['statutes'] as List),
    stage: enumByName(CaseStage.values, j['stage'], CaseStage.other),
    disposition: enumByName(
      CaseDisposition.values,
      j['disposition'],
      CaseDisposition.indeterminate,
    ),
    dispositionConfidence: (j['disposition_confidence'] as num).toDouble(),
    reviewStatus: enumByName(
      ReviewStatus.values,
      j['review_status'],
      ReviewStatus.awaitingReview,
    ),
    appearances: (j['appearances'] as List)
        .map((e) => Appearance.fromJson(e as Map<String, dynamic>))
        .toList(),
    sources: (j['sources'] as List)
        .map((e) => JudgmentSourceRef.fromJson(e as Map<String, dynamic>))
        .toList(),
    passages: (j['passages'] as List)
        .map((e) => Passage.fromJson(e as Map<String, dynamic>))
        .toList(),
    summary: j['summary'] as String,
    conflictNote: j['conflict_note'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'citation': citation,
    'case_number': caseNumber,
    'court_id': courtId,
    'bench_judge_ids': benchJudgeIds,
    'date': date.toIso8601String(),
    'category': category,
    'statutes': statutes,
    'stage': stage.name,
    'disposition': disposition.name,
    'disposition_confidence': dispositionConfidence,
    'review_status': reviewStatus.name,
    'appearances': appearances.map((a) => a.toJson()).toList(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'passages': passages.map((p) => p.toJson()).toList(),
    'summary': summary,
    'conflict_note': conflictNote,
  };
}
