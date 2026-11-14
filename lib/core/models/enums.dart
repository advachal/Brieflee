/// Shared domain enums. Every enum serialises by `name` for the REST API.
library;

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

enum SourceType {
  vakilaj('Vakilaj', 'Primary repository'),
  indianKanoon('Indian Kanoon', 'Secondary repository'),
  official('Official court record', 'Authoritative verification'),
  userUpload('Your upload', 'Private document');

  const SourceType(this.label, this.role);
  final String label;
  final String role;
}

enum VerificationStatus {
  verified('Verified'),
  unverified('Unverified'),
  conflicting('Conflicting sources'),
  pendingReview('Pending human review');

  const VerificationStatus(this.label);
  final String label;
}

enum RepresentationSide {
  petitioner('Petitioner', true),
  plaintiff('Plaintiff', true),
  appellant('Appellant', true),
  respondent('Respondent', false),
  defendant('Defendant', false);

  const RepresentationSide(this.label, this.isInitiating);
  final String label;

  /// True for the party that brought the proceeding.
  final bool isInitiating;
}

enum SideFilter {
  any('Any side'),
  initiating('Petitioner / plaintiff / appellant'),
  responding('Respondent / defendant');

  const SideFilter(this.label);
  final String label;

  bool accepts(RepresentationSide side) => switch (this) {
    SideFilter.any => true,
    SideFilter.initiating => side.isInitiating,
    SideFilter.responding => !side.isInitiating,
  };
}

enum CounselRole {
  senior('Senior counsel'),
  arguing('Arguing counsel'),
  onRecord('Advocate-on-record'),
  assisting('Assisting counsel');

  const CounselRole(this.label);
  final String label;
}

enum CaseStage {
  interimInjunction('Interim injunction'),
  finalHearing('Final hearing'),
  appeal('Appeal'),
  execution('Execution / enforcement'),
  other('Other / not sure');

  const CaseStage(this.label);
  final String label;
}

/// How a proceeding was disposed of, from the initiating party's perspective.
enum CaseDisposition {
  finalAllowed('Final: allowed / decreed', eligible: true),
  finalDismissed('Final: dismissed', eligible: true),
  partlyAllowed('Partly allowed (mixed relief)', eligible: true),
  interimGranted('Interim relief granted', eligible: true),
  interimRefused('Interim relief refused', eligible: true),
  settled('Settled', eligible: false),
  withdrawn('Withdrawn', eligible: false),
  procedural('Procedural disposal', eligible: false),
  indeterminate('Indeterminate', eligible: false);

  const CaseDisposition(this.label, {required this.eligible});
  final String label;

  /// Whether this disposition can enter a favourable-outcome denominator.
  final bool eligible;

  PartyOutcome outcomeFor(RepresentationSide side) {
    final forInitiator = switch (this) {
      CaseDisposition.finalAllowed ||
      CaseDisposition.interimGranted => PartyOutcome.favorable,
      CaseDisposition.finalDismissed ||
      CaseDisposition.interimRefused => PartyOutcome.unfavorable,
      CaseDisposition.partlyAllowed => PartyOutcome.mixed,
      _ => PartyOutcome.excluded,
    };
    if (side.isInitiating) return forInitiator;
    return switch (forInitiator) {
      PartyOutcome.favorable => PartyOutcome.unfavorable,
      PartyOutcome.unfavorable => PartyOutcome.favorable,
      _ => forInitiator,
    };
  }
}

enum PartyOutcome {
  favorable('Favorable'),
  unfavorable('Unfavorable'),
  mixed('Mixed'),
  excluded('Excluded');

  const PartyOutcome(this.label);
  final String label;
}

enum ReviewStatus {
  autoAccepted('Auto-accepted (high confidence)'),
  humanReviewed('Human reviewed'),
  awaitingReview('Awaiting review');

  const ReviewStatus(this.label);
  final String label;
}

enum EvidenceReliability {
  high('High'),
  moderate('Moderate'),
  low('Low'),
  insufficient('Insufficient');

  const EvidenceReliability(this.label);
  final String label;
}

enum JobStatus { queued, running, succeeded, failed }

enum IntakeMode {
  describe('Describe the matter'),
  upload('Upload documents'),
  caseNumber('Case number');

  const IntakeMode(this.label);
  final String label;
}

enum MatterStatus {
  draft('Draft'),
  analyzed('Analysis ready'),
  matched('Recommendations ready');

  const MatterStatus(this.label);
  final String label;
}
