import 'enums.dart';

/// A stable advocate identity. Aliases capture spelling variants that the
/// name-normalisation step has merged into this identity.
class Advocate {
  const Advocate({
    required this.id,
    required this.displayName,
    required this.aliases,
    required this.chamber,
    required this.practiceSince,
    required this.practiceAreas,
    required this.identityVerification,
  });

  final String id;
  final String displayName;
  final List<String> aliases;
  final String chamber;
  final int practiceSince;
  final List<String> practiceAreas;
  final VerificationStatus identityVerification;

  String get initials {
    final parts = displayName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.length == 1 ? parts.first[0] : parts.last[0];
  }

  factory Advocate.fromJson(Map<String, dynamic> j) => Advocate(
    id: j['id'] as String,
    displayName: j['display_name'] as String,
    aliases: List<String>.from(j['aliases'] as List),
    chamber: j['chamber'] as String,
    practiceSince: j['practice_since'] as int,
    practiceAreas: List<String>.from(j['practice_areas'] as List),
    identityVerification: enumByName(
      VerificationStatus.values,
      j['identity_verification'],
      VerificationStatus.unverified,
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'aliases': aliases,
    'chamber': chamber,
    'practice_since': practiceSince,
    'practice_areas': practiceAreas,
    'identity_verification': identityVerification.name,
  };
}

/// One counsel appearance in one judgment.
class Appearance {
  const Appearance({
    required this.advocateId,
    required this.side,
    required this.role,
    required this.verification,
    required this.confidence,
    this.supportingPassageId,
  });

  final String advocateId;
  final RepresentationSide side;
  final CounselRole role;
  final VerificationStatus verification;
  final double confidence;
  final String? supportingPassageId;

  bool get isVerified => verification == VerificationStatus.verified;

  factory Appearance.fromJson(Map<String, dynamic> j) => Appearance(
    advocateId: j['advocate_id'] as String,
    side: enumByName(
      RepresentationSide.values,
      j['side'],
      RepresentationSide.petitioner,
    ),
    role: enumByName(CounselRole.values, j['role'], CounselRole.arguing),
    verification: enumByName(
      VerificationStatus.values,
      j['verification'],
      VerificationStatus.unverified,
    ),
    confidence: (j['confidence'] as num).toDouble(),
    supportingPassageId: j['supporting_passage_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'advocate_id': advocateId,
    'side': side.name,
    'role': role.name,
    'verification': verification.name,
    'confidence': confidence,
    'supporting_passage_id': supportingPassageId,
  };
}
