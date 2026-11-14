import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/widgets/common.dart';

/// Sign-in and account. Production: Firebase Auth or managed OIDC.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.from});
  final String? from;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  UserRole _role = UserRole.dataAdmin;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await ref
        .read(authControllerProvider.notifier)
        .signInDemo(email: _email.text.trim(), role: _role);
    if (!mounted) return;
    setState(() => _busy = false);
    context.go(widget.from ?? Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    final t = Theme.of(context).textTheme;

    if (user != null) {
      return PageBody(
        maxWidth: 560,
        children: [
          const PageHeader(
            title: 'Account',
            subtitle: 'Signed in (demo session)',
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValueRow('Name', user.name),
                KeyValueRow('Email', user.email),
                KeyValueRow('Organization', user.organization),
                KeyValueRow('Role', user.role.label),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => context.go(Routes.settings),
                      icon: const Icon(Icons.tune),
                      label: const Text('Preferences & privacy'),
                    ),
                    if (user.canAdminister)
                      OutlinedButton.icon(
                        onPressed: () => context.go(Routes.admin),
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Admin dashboard'),
                      ),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return PageBody(
      maxWidth: 460,
      children: [
        const SizedBox(height: 12),
        Text('Sign in', style: t.headlineMedium),
        const SizedBox(height: 6),
        Text(
          widget.from == Routes.admin
              ? 'The admin dashboard needs an administrator account.'
              : 'Save matters, shortlists and alerts across devices.',
          style: t.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Work email'),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email address'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'At least 6 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  isExpanded: true,
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Demo role'),
                  items: [
                    for (final r in UserRole.values)
                      DropdownMenuItem(value: r, child: Text(r.label)),
                  ],
                  onChanged: (r) => setState(() => _role = r ?? _role),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          _email.text = 'demo@example.com';
                          _password.text = 'demo-only';
                          _signIn();
                        },
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Continue with organization SSO (demo)'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Demo only: no credentials are checked, stored or sent. Production '
          'sign-in will use Firebase Auth or a managed OIDC provider.',
          style: t.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}
