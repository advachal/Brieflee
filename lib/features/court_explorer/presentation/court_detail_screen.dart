import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../../judge_roster/application/roster_providers.dart';
import '../application/court_providers.dart';

class CourtDetailScreen extends ConsumerWidget {
  const CourtDetailScreen({super.key, required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final court = ref.watch(courtProvider(courtId));
    return AsyncView<Court>(
      value: court,
      onRetry: () => ref.invalidate(courtProvider(courtId)),
      builder: (c) {
        final pilot = c.support == CourtSupport.pilot;
        return PageBody(
          children: [
            PageHeader(
              title: c.name,
              subtitle: '${c.type.label} · ${c.jurisdiction}',
              leading: IconButton(
                tooltip: 'Back to courts',
                onPressed: () => context.go(Routes.courts),
                icon: const Icon(Icons.arrow_back),
              ),
              actions: [
                if (pilot)
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.judges(court: c.id)),
                    icon: const Icon(Icons.gavel),
                    label: const Text('Judges & roster'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => context.go(Routes.newMatter),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Start a matter here'),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, box) {
                final divisions = SectionCard(
                  title: 'Divisions',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final d in c.divisions)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.subdirectory_arrow_right,
                            color: AppColors.teal,
                          ),
                          title: Text(d),
                        ),
                    ],
                  ),
                );
                final categories = SectionCard(
                  title: 'Case categories',
                  subtitle: pilot
                      ? 'Pilot scope: IP, commercial and interim injunctions'
                      : null,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final x in c.caseCategories) Chip(label: Text(x)),
                    ],
                  ),
                );
                if (box.maxWidth < 760) {
                  return Column(
                    children: [
                      divisions,
                      const SizedBox(height: 14),
                      categories,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: divisions),
                    const SizedBox(width: 14),
                    Expanded(child: categories),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            if (pilot)
              _RosterSummary(courtId: c.id)
            else
              const SectionCard(
                title: 'Roster monitoring',
                child: Text(
                  'Not yet monitored. This court is planned after the pilot.',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RosterSummary extends ConsumerWidget {
  const _RosterSummary({required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider(courtId));
    return SectionCard(
      title: 'Roster verification',
      subtitle: 'Official source, effective date and last successful check',
      child: roster.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
        data: (r) => r == null
            ? const Text('No roster on record.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValueRow('Current version', r.current.label),
                  KeyValueRow(
                    'Effective from',
                    formatDate(r.current.effectiveFrom),
                  ),
                  KeyValueRow('Source', r.current.sourceLabel),
                  KeyValueRow(
                    'Last successful check',
                    formatDateTime(r.current.lastCheckedAt),
                  ),
                  KeyValueRow(
                    'Status',
                    '',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: VerificationBadge(r.current.verification),
                    ),
                  ),
                  KeyValueRow(
                    'Previous versions',
                    '${r.history.length} kept in history',
                  ),
                ],
              ),
      ),
    );
  }
}
