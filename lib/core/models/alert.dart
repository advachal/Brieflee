import 'enums.dart';

enum AlertKind {
  rosterChange('Roster change'),
  listingChange('Listing update'),
  benchChange('Bench change'),
  newJudgment('Relevant judgment'),
  recommendationUpdated('Recommendations updated');

  const AlertKind(this.label);
  final String label;
}

class AlertSubscription {
  const AlertSubscription({
    required this.id,
    required this.label,
    required this.kinds,
    required this.createdAt,
    required this.active,
    this.matterId,
    this.courtId,
  });

  final String id;
  final String label;
  final Set<AlertKind> kinds;
  final DateTime createdAt;
  final bool active;
  final String? matterId;
  final String? courtId;

  AlertSubscription copyWith({bool? active}) => AlertSubscription(
    id: id,
    label: label,
    kinds: kinds,
    createdAt: createdAt,
    active: active ?? this.active,
    matterId: matterId,
    courtId: courtId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'kinds': kinds.map((k) => k.name).toList(),
    'created_at': createdAt.toIso8601String(),
    'active': active,
    'matter_id': matterId,
    'court_id': courtId,
  };

  factory AlertSubscription.fromJson(Map<String, dynamic> j) =>
      AlertSubscription(
        id: j['id'] as String,
        label: j['label'] as String,
        kinds: (j['kinds'] as List)
            .map(
              (k) => enumByName(AlertKind.values, k, AlertKind.listingChange),
            )
            .toSet(),
        createdAt: DateTime.parse(j['created_at'] as String),
        active: j['active'] as bool,
        matterId: j['matter_id'] as String?,
        courtId: j['court_id'] as String?,
      );
}

class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    required this.verification,
    this.read = false,
    this.matterId,
    this.previousValue,
    this.currentValue,
  });

  final String id;
  final AlertKind kind;
  final String title;
  final String body;
  final DateTime at;
  final VerificationStatus verification;
  final bool read;
  final String? matterId;
  final String? previousValue;
  final String? currentValue;

  AlertEvent markRead() => AlertEvent(
    id: id,
    kind: kind,
    title: title,
    body: body,
    at: at,
    verification: verification,
    read: true,
    matterId: matterId,
    previousValue: previousValue,
    currentValue: currentValue,
  );
}
