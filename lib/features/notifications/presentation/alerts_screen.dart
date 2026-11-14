import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../application/alert_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  IconData _icon(AlertKind k) => switch (k) {
    AlertKind.rosterChange => Icons.event_note,
    AlertKind.listingChange => Icons.list_alt,
    AlertKind.benchChange => Icons.swap_horiz,
    AlertKind.newJudgment => Icons.menu_book_outlined,
    AlertKind.recommendationUpdated => Icons.auto_graph,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(alertEventsProvider);
    final subs = ref.watch(alertSubscriptionsProvider);
    final repo = ref.read(alertRepositoryProvider);
    final t = Theme.of(context).textTheme;

    return PageBody(
      maxWidth: 900,
      children: [
        PageHeader(
          title: 'Alerts',
          subtitle: 'Verified roster, listing and judgment changes for what you monitor',
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await repo.markAllRead();
                ref.invalidate(alertEventsProvider);
              },
              icon: const Icon(Icons.done_all),
              label: const Text('Mark all read'),
            ),
          ],
        ),
        AsyncView<List<AlertEvent>>(
          value: events,
          builder: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none,
                  title: 'No alerts',
                  message:
                      'Monitor a matter or court to receive verified updates.',
                )
              : Column(
                  children: [
                    for (final e in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: e.read
                            ? AppColors.surface
                            : AppColors.tealSoft.withValues(alpha: 0.35),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            await repo.markRead(e.id);
                            ref.invalidate(alertEventsProvider);
                            if (e.matterId != null &&
                                context.mounted &&
                                e.kind == AlertKind.recommendationUpdated) {
                              context.go(Routes.results('rec-demo-1'));
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.navy,
                                  child: Icon(
                                    _icon(e.kind),
                                    color: AppColors.gold,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(e.title, style: t.titleSmall),
                                          if (!e.read)
                                            const Pill(
                                              label: 'New',
                                              color: AppColors.teal,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(e.body, style: t.bodyMedium),
                                      if (e.previousValue != null &&
                                          e.currentValue != null) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.offWhite,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Before: ${e.previousValue}\nNow: ${e.currentValue}',
                                            style: t.bodySmall,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          Pill(
                                            label: e.kind.label,
                                            color: AppColors.navy,
                                          ),
                                          VerificationBadge(
                                            e.verification,
                                            compact: true,
                                          ),
                                          Text(
                                            relativeTime(e.at),
                                            style: t.bodySmall?.copyWith(
                                              color: AppColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        Text('Monitoring subscriptions', style: t.titleMedium),
        const SizedBox(height: 10),
        AsyncView<List<AlertSubscription>>(
          value: subs,
          builder: (list) => Card(
            child: Column(
              children: [
                for (final s in list)
                  SwitchListTile(
                    value: s.active,
                    onChanged: (v) async {
                      await repo.setActive(s.id, v);
                      ref.invalidate(alertSubscriptionsProvider);
                    },
                    title: Text(s.label),
                    subtitle: Text(s.kinds.map((k) => k.label).join(' · ')),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Production delivery: Firebase Cloud Messaging and email. Only verified '
          'changes trigger alerts; unverified changes are queued for review.',
          style: t.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}
