import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/mock/demo_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../../case_intake/application/matter_providers.dart';

class SavedMattersScreen extends ConsumerWidget {
  const SavedMattersScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Matter m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this matter?'),
        content: Text(
          '"${m.title}", its ${m.documents.length} document(s), analysis, '
          'shortlist and recommendation history will be permanently deleted.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(matterRepositoryProvider).delete(m.id);
    refreshMatters(ref, m.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Matter and private data deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matters = ref.watch(mattersProvider);
    final data = ref.watch(demoDatasetProvider);
    final t = Theme.of(context).textTheme;

    return PageBody(
      children: [
        PageHeader(
          title: 'Saved matters',
          subtitle:
              'Your matters, documents, shortlists and recommendation history',
          actions: [
            FilledButton.icon(
              onPressed: () => context.go(Routes.newMatter),
              icon: const Icon(Icons.add),
              label: const Text('New matter'),
            ),
          ],
        ),
        AsyncView<List<Matter>>(
          value: matters,
          onRetry: () => ref.invalidate(mattersProvider),
          builder: (list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.bookmark_border,
                title: 'No saved matters yet',
                message: 'Start a matter to save its analysis, shortlist and alerts here.',
                action: FilledButton(
                  onPressed: () => context.go(Routes.newMatter),
                  child: const Text('Start a matter'),
                ),
              );
            }
            return Column(
              children: [
                for (final m in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.title, style: t.titleMedium),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Created ${formatDateTime(m.createdAt)}',
                                      style: t.bodySmall?.copyWith(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete matter and private data',
                                onPressed: () => _delete(context, ref, m),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Pill(
                                label: m.status.label,
                                color: AppColors.teal,
                              ),
                              if (m.caseNumber != null)
                                Pill(
                                  label: m.caseNumber!,
                                  color: AppColors.navy,
                                  icon: Icons.tag,
                                ),
                              if (m.analysis != null)
                                Pill(
                                  label: m.analysis!.caseCategory,
                                  color: AppColors.navy,
                                ),
                              Pill(
                                label: '${m.documents.length} documents',
                                color: AppColors.neutral,
                                icon: Icons.attach_file,
                              ),
                              if (m.monitored)
                                const Pill(
                                  label: 'Monitoring',
                                  color: AppColors.favorable,
                                  icon: Icons.notifications_active,
                                ),
                            ],
                          ),
                          if (m.shortlist.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Shortlist', style: t.labelLarge),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final id in m.shortlist)
                                  ActionChip(
                                    avatar: const Icon(
                                      Icons.bookmark,
                                      size: 16,
                                      color: AppColors.gold,
                                    ),
                                    label: Text(
                                      data.advocate(id)?.displayName ?? id,
                                    ),
                                    onPressed: () => context.push(
                                      Routes.advocate(
                                        id,
                                        rec: m.recommendationIds.isEmpty
                                            ? (m.id == 'm-demo-1'
                                                  ? 'rec-demo-1'
                                                  : null)
                                            : m.recommendationIds.last,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.go(Routes.analysis(m.id)),
                                icon: const Icon(Icons.edit_note),
                                label: const Text('Analysis'),
                              ),
                              if (m.recommendationIds.isNotEmpty ||
                                  m.id == 'm-demo-1')
                                FilledButton.icon(
                                  onPressed: () => context.go(
                                    Routes.results(
                                      m.recommendationIds.isEmpty
                                          ? 'rec-demo-1'
                                          : m.recommendationIds.last,
                                    ),
                                  ),
                                  icon: const Icon(Icons.people_outline),
                                  label: const Text('Recommendations'),
                                ),
                            ],
                          ),
                          if (m.recommendationIds.length > 1) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${m.recommendationIds.length} recommendation runs kept in history',
                              style: t.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
