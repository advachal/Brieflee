import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UserRole {
  member('Member'),
  orgAdmin('Organization admin'),
  dataAdmin('Data-quality admin');

  const UserRole(this.label);
  final String label;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.organization,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String organization;

  bool get canAdminister => role != UserRole.member;
}

/// Demo authentication. Production uses Firebase Auth or a managed OIDC
/// provider; no credentials are stored or sent anywhere in this build.
class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> signInDemo({
    required String email,
    UserRole role = UserRole.dataAdmin,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final name = email.contains('@') ? email.split('@').first : 'Demo user';
    state = AppUser(
      id: 'demo-user',
      name: name.isEmpty ? 'Demo user' : name,
      email: email.isEmpty ? 'demo@example.com' : email,
      role: role,
      organization: 'Demo Legal Team',
    );
  }

  void signOut() => state = null;
}

final authControllerProvider = NotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);
