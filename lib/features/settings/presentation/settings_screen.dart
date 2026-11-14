import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/common.dart';
import '../../ask/application/ask_providers.dart';
import '../../saved/application/saved_store.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final saved = ref.watch(savedProvider);
    final service = ref.watch(knowledgeServiceProvider);
    return PageBody(
      maxWidth: 780,
      children: [
        const PageHeader(
          title: 'Settings and privacy',
          subtitle: 'Where the answers come from and what stays on your device',
        ),
        SectionCard(
          title: 'Your data',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Searches run in your browser. Documents you upload are read here and are not stored. '
                'When the analysis service is switched on, the document text is sent to it for that one '
                'analysis and is not kept.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '${saved.counsel.length} saved advocates, ${saved.searches.length} saved searches on this device.',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: saved.counsel.isEmpty && saved.searches.isEmpty
                    ? null
                    : () {
                        final s = ref.read(savedProvider.notifier);
                        for (final e in saved.counsel.entries.toList()) {
                          s.toggleCounsel(e.key, e.value);
                        }
                        for (final q in saved.searches.toList()) {
                          s.toggleSearch(q);
                        }
                      },
                child: const Text('Clear saved items'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Sources',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppConfig.publicRecordsNotice, style: t.bodyMedium),
              const SizedBox(height: 12),
              Text(
                service.configured ? 'AI document analysis: connected.' : 'AI document analysis: not connected. Uploads are matched on this device by key terms and statutes.',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
