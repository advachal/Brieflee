import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../application/roster_providers.dart';

/// Shows the bench identified from the latest cause list, with source and
/// freshness, or lets the user choose judges manually.
class BenchIntelligenceCard extends ConsumerWidget {
  const BenchIntelligenceCard({
    super.key,
    required this.courtId,
    required this.caseNumber,
    required this.manualJudgeIds,
    required this.onManualChanged,
    this.onListingResolved,
  });

  final String courtId;
  final String? caseNumber;
  final Set<String> manualJudgeIds;
  final ValueChanged<Set<String>> onManualChanged;
  final ValueChanged<CaseListing>? onListingResolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final roster = ref.watch(rosterProvider(courtId));

    Widget rosterLine() => roster.when(
      data: (r) => r == null
          ? const Text('No roster available for this court yet.')
          : Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${r.current.label} · effective ${formatDate(r.current.effectiveFrom)}',
                  style: t.bodySmall,
                ),
                VerificationBadge(r.current.verification, compact: true),
                Text(
                  'Last checked ${relativeTime(r.current.lastCheckedAt)}',
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Roster unavailable: $e'),
    );

    final hasCase = caseNumber != null && caseNumber!.trim().isNotEmpty;

    return SectionCard(
      title: 'Bench intelligence',
      subtitle: 'From the official roster and cause list (demo placeholders)',
      trailing: TextButton(
        onPressed: () => context.go(Routes.judges(court: courtId)),
        child: const Text('Judge explorer'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rosterLine(),
          const Divider(height: 24),
          if (hasCase)
            _ListingView(
              courtId: courtId,
              caseNumber: caseNumber!,
              onResolved: onListingResolved,
            )
          else
            Text(
              'No case number given, so no bench was identified. You can pick '
              'judges below to include judge-specific experience, or skip it.',
              style: t.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          const SizedBox(height: 12),
          _ManualBenchPicker(
            courtId: courtId,
            selected: manualJudgeIds,
            onChanged: onManualChanged,
            label: hasCase
                ? 'Override bench (optional)'
                : 'Choose judges (optional)',
          ),
        ],
      ),
    );
  }
}

class _ListingView extends ConsumerWidget {
  const _ListingView({
    required this.courtId,
    required this.caseNumber,
    this.onResolved,
  });
  final String courtId;
  final String caseNumber;
  final ValueChanged<CaseListing>? onResolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final listing = ref.watch(
      caseListingProvider((courtId: courtId, caseNumber: caseNumber)),
    );
    return listing.when(
      loading: () => const Text('Checking the latest cause list…'),
      error: (e, _) => Text('Could not check listings: $e'),
      data: (l) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onResolved?.call(l),
        );
        if (l.status == ListingStatus.notFound) {
          return Row(
            children: [
              const Icon(Icons.help_outline, color: AppColors.neutral),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$caseNumber was not found in the latest cause list. Bench '
                  'status is unverified; this does not mean the matter is not listed.',
                ),
              ),
            ],
          );
        }
        String names(List<String> ids) =>
            ids.map((id) => ref.watch(judgeNameProvider(id))).join(' & ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(names(l.benchJudgeIds), style: t.titleMedium),
                VerificationBadge(l.verification),
                if (l.status == ListingStatus.benchChanged)
                  const Pill(
                    label: 'Bench changed',
                    color: AppColors.mixed,
                    icon: Icons.swap_horiz,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${l.courtRoom} · Item ${l.itemNumber} · ${formatDate(l.listingDate)}',
              style: t.bodyMedium,
            ),
            Text(
              '${l.causeListLabel} · checked ${relativeTime(l.lastCheckedAt)}',
              style: t.bodySmall?.copyWith(color: AppColors.muted),
            ),
            if (l.previousBenchJudgeIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Previously listed before ${names(l.previousBenchJudgeIds)}. '
                  'That assignment is kept in history; experience before it still counts '
                  'as general experience, and judge matching now uses the current bench.',
                  style: t.bodySmall,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ManualBenchPicker extends ConsumerWidget {
  const _ManualBenchPicker({
    required this.courtId,
    required this.selected,
    required this.onChanged,
    required this.label,
  });

  final String courtId;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final judges = ref.watch(judgesProvider(courtId));
    return judges.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final j in list.where((j) => j.isSitting))
                FilterChip(
                  label: Text(j.name),
                  selected: selected.contains(j.id),
                  onSelected: (on) => onChanged(
                    on ? {...selected, j.id} : ({...selected}..remove(j.id)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
