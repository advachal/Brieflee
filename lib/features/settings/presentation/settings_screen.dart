import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../../shared/constants/breakpoints.dart';
import '../../case_intake/application/matter_providers.dart';
import '../application/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all my data?'),
        content: const Text(
          'All matters, uploaded documents, analyses, shortlists and '
          'alerts will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.unfavorable,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(matterRepositoryProvider).deleteAll();
    refreshMatters(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All your matter data was deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(preferencesProvider);
    final ctl = ref.read(preferencesProvider.notifier);
    final t = Theme.of(context).textTheme;

    return PageBody(
      maxWidth: 780,
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Privacy, notifications and your data',
        ),
        SectionCard(
          title: 'Privacy',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: p.redactBeforeAi,
                onChanged: (v) => ctl.update(p.copyWith(redactBeforeAi: v)),
                title: const Text(
                  'Redact personal details before AI processing',
                ),
                subtitle: const Text(
                  'Names, contact details and identifiers are masked '
                  'before any external model sees the text.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: p.shareWithOrganization,
                onChanged: (v) =>
                    ctl.update(p.copyWith(shareWithOrganization: v)),
                title: const Text(
                  'Share matters with my organization workspace',
                ),
                subtitle: const Text(
                  'Off by default. Data stays isolated per organization.',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep uploaded documents for'),
                trailing: DropdownButton<int>(
                  value: p.retentionDays,
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                    DropdownMenuItem(value: 90, child: Text('90 days')),
                    DropdownMenuItem(value: 365, child: Text('1 year')),
                  ],
                  onChanged: (v) => ctl.update(p.copyWith(retentionDays: v)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Notifications',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: p.pushAlerts,
                onChanged: (v) => ctl.update(p.copyWith(pushAlerts: v)),
                title: const Text('Push notifications'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: p.emailAlerts,
                onChanged: (v) => ctl.update(p.copyWith(emailAlerts: v)),
                title: const Text('Email alerts'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: p.weeklyDigest,
                onChanged: (v) => ctl.update(p.copyWith(weeklyDigest: v)),
                title: const Text(
                  'Weekly digest of roster and judgment changes',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Your data',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You can delete individual matters from Saved matters, or remove '
                'everything here.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.unfavorable,
                  side: const BorderSide(color: AppColors.unfavorable),
                ),
                onPressed: () => _deleteAll(context, ref),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Delete all my data'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'About this prototype',
          child: Text(
            'Brieflee prototype, phase 1. Live judgment sources (Vakilaj, '
            'Indian Kanoon) and official court feeds are not connected. All data is '
            'fictional and illustrative.\n\n${AppStrings.outcomeDisclaimer}',
            style: t.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
