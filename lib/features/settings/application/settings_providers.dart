import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserPreferences {
  const UserPreferences({
    this.redactBeforeAi = true,
    this.retentionDays = 90,
    this.pushAlerts = true,
    this.emailAlerts = true,
    this.weeklyDigest = false,
    this.shareWithOrganization = false,
  });

  final bool redactBeforeAi;
  final int retentionDays;
  final bool pushAlerts;
  final bool emailAlerts;
  final bool weeklyDigest;
  final bool shareWithOrganization;

  UserPreferences copyWith({
    bool? redactBeforeAi,
    int? retentionDays,
    bool? pushAlerts,
    bool? emailAlerts,
    bool? weeklyDigest,
    bool? shareWithOrganization,
  }) => UserPreferences(
    redactBeforeAi: redactBeforeAi ?? this.redactBeforeAi,
    retentionDays: retentionDays ?? this.retentionDays,
    pushAlerts: pushAlerts ?? this.pushAlerts,
    emailAlerts: emailAlerts ?? this.emailAlerts,
    weeklyDigest: weeklyDigest ?? this.weeklyDigest,
    shareWithOrganization: shareWithOrganization ?? this.shareWithOrganization,
  );
}

class PreferencesController extends Notifier<UserPreferences> {
  @override
  UserPreferences build() => const UserPreferences();

  void update(UserPreferences p) => state = p;
}

final preferencesProvider =
    NotifierProvider<PreferencesController, UserPreferences>(
      PreferencesController.new,
    );
