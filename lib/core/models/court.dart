import 'enums.dart';

enum CourtType {
  supremeCourt('Supreme Court'),
  highCourt('High Court'),
  tribunal('Tribunal');

  const CourtType(this.label);
  final String label;
}

enum CourtSupport {
  pilot('Pilot (demo data)'),
  planned('Planned');

  const CourtSupport(this.label);
  final String label;
}

class Court {
  const Court({
    required this.id,
    required this.name,
    required this.shortName,
    required this.type,
    required this.jurisdiction,
    required this.divisions,
    required this.caseCategories,
    required this.support,
  });

  final String id;
  final String name;
  final String shortName;
  final CourtType type;
  final String jurisdiction;
  final List<String> divisions;
  final List<String> caseCategories;
  final CourtSupport support;

  factory Court.fromJson(Map<String, dynamic> j) => Court(
    id: j['id'] as String,
    name: j['name'] as String,
    shortName: j['short_name'] as String,
    type: enumByName(CourtType.values, j['type'], CourtType.highCourt),
    jurisdiction: j['jurisdiction'] as String,
    divisions: List<String>.from(j['divisions'] as List),
    caseCategories: List<String>.from(j['case_categories'] as List),
    support: enumByName(
      CourtSupport.values,
      j['support'],
      CourtSupport.planned,
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'short_name': shortName,
    'type': type.name,
    'jurisdiction': jurisdiction,
    'divisions': divisions,
    'case_categories': caseCategories,
    'support': support.name,
  };
}

class Judge {
  const Judge({
    required this.id,
    required this.name,
    required this.courtId,
    required this.designation,
    required this.isSitting,
    required this.verification,
  });

  final String id;
  final String name;
  final String courtId;
  final String designation;
  final bool isSitting;
  final VerificationStatus verification;

  factory Judge.fromJson(Map<String, dynamic> j) => Judge(
    id: j['id'] as String,
    name: j['name'] as String,
    courtId: j['court_id'] as String,
    designation: j['designation'] as String,
    isSitting: j['is_sitting'] as bool,
    verification: enumByName(
      VerificationStatus.values,
      j['verification'],
      VerificationStatus.unverified,
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'court_id': courtId,
    'designation': designation,
    'is_sitting': isSitting,
    'verification': verification.name,
  };
}

class BenchAssignment {
  const BenchAssignment({
    required this.benchId,
    required this.judgeIds,
    required this.courtRoom,
    required this.subjects,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  final String benchId;
  final List<String> judgeIds;
  final String courtRoom;
  final List<String> subjects;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;

  bool get isDivisionBench => judgeIds.length > 1;

  factory BenchAssignment.fromJson(Map<String, dynamic> j) => BenchAssignment(
    benchId: j['bench_id'] as String,
    judgeIds: List<String>.from(j['judge_ids'] as List),
    courtRoom: j['court_room'] as String,
    subjects: List<String>.from(j['subjects'] as List),
    effectiveFrom: DateTime.parse(j['effective_from'] as String),
    effectiveTo: j['effective_to'] == null
        ? null
        : DateTime.parse(j['effective_to'] as String),
  );

  Map<String, dynamic> toJson() => {
    'bench_id': benchId,
    'judge_ids': judgeIds,
    'court_room': courtRoom,
    'subjects': subjects,
    'effective_from': effectiveFrom.toIso8601String(),
    'effective_to': effectiveTo?.toIso8601String(),
  };
}

/// One published version of an official roster.
class RosterVersion {
  const RosterVersion({
    required this.id,
    required this.courtId,
    required this.label,
    required this.effectiveFrom,
    required this.lastCheckedAt,
    required this.sourceLabel,
    required this.verification,
    required this.assignments,
    this.sourceUrl,
  });

  final String id;
  final String courtId;
  final String label;
  final DateTime effectiveFrom;
  final DateTime lastCheckedAt;
  final String sourceLabel;
  final String? sourceUrl;
  final VerificationStatus verification;
  final List<BenchAssignment> assignments;

  factory RosterVersion.fromJson(Map<String, dynamic> j) => RosterVersion(
    id: j['id'] as String,
    courtId: j['court_id'] as String,
    label: j['label'] as String,
    effectiveFrom: DateTime.parse(j['effective_from'] as String),
    lastCheckedAt: DateTime.parse(j['last_checked_at'] as String),
    sourceLabel: j['source_label'] as String,
    sourceUrl: j['source_url'] as String?,
    verification: enumByName(
      VerificationStatus.values,
      j['verification'],
      VerificationStatus.unverified,
    ),
    assignments: (j['assignments'] as List)
        .map((e) => BenchAssignment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'court_id': courtId,
    'label': label,
    'effective_from': effectiveFrom.toIso8601String(),
    'last_checked_at': lastCheckedAt.toIso8601String(),
    'source_label': sourceLabel,
    'source_url': sourceUrl,
    'verification': verification.name,
    'assignments': assignments.map((a) => a.toJson()).toList(),
  };
}

/// The latest roster plus every earlier version, which is kept because past
/// experience before a judge stays relevant after a roster change.
class CourtRoster {
  const CourtRoster({required this.current, required this.history});
  final RosterVersion current;
  final List<RosterVersion> history;
}

enum ListingStatus {
  scheduled('Scheduled'),
  benchChanged('Bench changed'),
  adjourned('Adjourned'),
  notFound('Not found in latest cause list');

  const ListingStatus(this.label);
  final String label;
}

class CaseListing {
  const CaseListing({
    required this.caseNumber,
    required this.courtId,
    required this.listingDate,
    required this.benchJudgeIds,
    required this.courtRoom,
    required this.itemNumber,
    required this.causeListLabel,
    required this.status,
    required this.verification,
    required this.lastCheckedAt,
    this.previousBenchJudgeIds = const [],
  });

  final String caseNumber;
  final String courtId;
  final DateTime listingDate;
  final List<String> benchJudgeIds;
  final List<String> previousBenchJudgeIds;
  final String courtRoom;
  final int itemNumber;
  final String causeListLabel;
  final ListingStatus status;
  final VerificationStatus verification;
  final DateTime lastCheckedAt;

  factory CaseListing.fromJson(Map<String, dynamic> j) => CaseListing(
    caseNumber: j['case_number'] as String,
    courtId: j['court_id'] as String,
    listingDate: DateTime.parse(j['listing_date'] as String),
    benchJudgeIds: List<String>.from(j['bench_judge_ids'] as List),
    previousBenchJudgeIds: List<String>.from(
      (j['previous_bench_judge_ids'] as List?) ?? [],
    ),
    courtRoom: j['court_room'] as String,
    itemNumber: j['item_number'] as int,
    causeListLabel: j['cause_list_label'] as String,
    status: enumByName(
      ListingStatus.values,
      j['status'],
      ListingStatus.notFound,
    ),
    verification: enumByName(
      VerificationStatus.values,
      j['verification'],
      VerificationStatus.unverified,
    ),
    lastCheckedAt: DateTime.parse(j['last_checked_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'case_number': caseNumber,
    'court_id': courtId,
    'listing_date': listingDate.toIso8601String(),
    'bench_judge_ids': benchJudgeIds,
    'previous_bench_judge_ids': previousBenchJudgeIds,
    'court_room': courtRoom,
    'item_number': itemNumber,
    'cause_list_label': causeListLabel,
    'status': status.name,
    'verification': verification.name,
    'last_checked_at': lastCheckedAt.toIso8601String(),
  };
}

class SittingNotice {
  const SittingNotice({
    required this.id,
    required this.courtId,
    required this.date,
    required this.description,
    required this.affectedJudgeIds,
    required this.verification,
  });

  final String id;
  final String courtId;
  final DateTime date;
  final String description;
  final List<String> affectedJudgeIds;
  final VerificationStatus verification;
}
