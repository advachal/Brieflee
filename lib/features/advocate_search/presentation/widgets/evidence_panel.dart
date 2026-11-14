import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/models.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/status_badges.dart';
import '../../../../shared/utilities/formatters.dart';
import '../../../judgment_viewer/application/judgment_providers.dart';
import '../../../judgment_viewer/presentation/case_list_sheet.dart';
import '../../application/recommendation_providers.dart';

/// Metrics grid where every number opens the cases behind it.
class TraceableMetrics extends StatelessWidget {
  const TraceableMetrics({super.key, required this.item, this.columns = 2});
  final RecommendationItem item;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final m = item.metrics;
    final id = item.advocate.id;
    void open(String title, List<String> ids, [String? note]) =>
        showCaseListSheet(
          context,
          title: title,
          judgmentIds: ids,
          advocateId: id,
          explanation: note,
        );

    final tiles = <Widget>[
      MetricTile(
        label: 'Comparable cases',
        value: '${m.comparableIds.length}',
        onTap: () => open(
          'Comparable cases',
          m.comparableIds,
          'Same case type (and stage, if filtered) within the time range.',
        ),
      ),
      MetricTile(
        label: 'Verified appearances',
        value: '${m.verifiedAppearanceIds.length}',
        hint: 'of ${m.allAppearanceIds.length} recorded',
        onTap: () => open(
          'Verified appearances',
          m.verifiedAppearanceIds,
          'Appearance and representation side confirmed against the judgment text.',
        ),
      ),
      MetricTile(
        label: 'Favorable',
        value: '${m.favorableIds.length}/${m.eligibleIds.length}',
        hint: 'eligible outcomes',
        color: AppColors.favorable,
        onTap: () => open('Favorable outcomes', m.favorableIds),
      ),
      MetricTile(
        label: 'Unfavorable',
        value: '${m.unfavorableIds.length}',
        color: AppColors.unfavorable,
        onTap: () => open('Unfavorable outcomes', m.unfavorableIds),
      ),
      MetricTile(
        label: 'Mixed relief',
        value: '${m.mixedIds.length}',
        color: AppColors.mixed,
        onTap: () => open('Mixed / partial relief', m.mixedIds),
      ),
      MetricTile(
        label: 'Excluded from rate',
        value: '${m.excludedIds.length}',
        color: AppColors.neutral,
        onTap: () => open(
          'Excluded from outcome rate',
          m.excludedIds,
          'Settled, withdrawn, procedural, indeterminate, or counsel role not yet verified.',
        ),
      ),
      MetricTile(
        label: 'Same forum',
        value: '${m.forumIds.length}',
        onTap: () => open('Matters in the same forum', m.forumIds),
      ),
      MetricTile(
        label: 'Before identified bench',
        value: item.components.judgeApplied ? '${m.judgeIds.length}' : '—',
        onTap: item.components.judgeApplied
            ? () => open(
                'Matters before the identified bench',
                m.judgeIds,
                'Documented litigation experience only. Not an indication of any judge\'s view.',
              )
            : null,
      ),
      MetricTile(
        label: 'Search hits',
        value: '${m.searchHits}',
        hint: '${m.mentionOnly} mention-only',
        color: AppColors.neutral,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class ScoreBreakdown extends ConsumerWidget {
  const ScoreBreakdown({super.key, required this.item});
  final RecommendationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(scoringWeightsProvider);
    final c = item.components;
    return Column(
      children: [
        ComponentBar(
          label: 'Comparable case experience',
          value: c.comparable,
          weight: w.comparable,
        ),
        ComponentBar(
          label: 'Court / forum experience',
          value: c.forum,
          weight: w.forum,
        ),
        ComponentBar(
          label: 'Judge / bench experience',
          value: c.judge,
          weight: w.judge,
          applied: c.judgeApplied,
        ),
        ComponentBar(
          label: 'Verified outcome evidence',
          value: c.outcome,
          weight: w.outcome,
        ),
        ComponentBar(
          label: 'Recency of experience',
          value: c.recency,
          weight: w.recency,
        ),
        ComponentBar(
          label: 'Counsel role verification',
          value: c.roleVerification,
          weight: w.roleVerification,
        ),
      ],
    );
  }
}

/// Right-hand panel on desktop: why this advocate, and the evidence.
class EvidencePanel extends ConsumerWidget {
  const EvidencePanel({
    super.key,
    required this.item,
    required this.recommendationId,
    this.scroll,
  });

  final RecommendationItem? item;
  final String recommendationId;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final it = item;
    if (it == null) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'Select an advocate',
        message: 'Choose an advocate to see the judgments and methodology behind the match.',
      );
    }
    final top = it.metrics.comparableIds.take(4).join(',');
    final topCases = ref.watch(judgmentsByIdsProvider(top));

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Why ${it.advocate.displayName}?',
                style: t.titleMedium,
              ),
            ),
            const IllustrativeTag(),
          ],
        ),
        const SizedBox(height: 6),
        Text(it.headline, style: t.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Pill(
              label: 'Match ${it.score.round()}%',
              color: AppColors.navy,
              tooltip: 'Match relevance under the current methodology',
            ),
            ReliabilityBadge(it.reliability),
          ],
        ),
        const SizedBox(height: 16),
        for (final r in it.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(r, style: t.bodySmall)),
              ],
            ),
          ),
        for (final l in it.limitations)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.mixed,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l, style: t.bodySmall)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text('Case-level evidence', style: t.titleSmall),
        const SizedBox(height: 8),
        TraceableMetrics(item: it),
        const SizedBox(height: 18),
        Text('Score breakdown', style: t.titleSmall),
        const SizedBox(height: 4),
        ScoreBreakdown(item: it),
        const SizedBox(height: 18),
        Text('Most relevant judgments', style: t.titleSmall),
        const SizedBox(height: 8),
        topCases.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => Column(
            children: [
              for (final j in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: JudgmentEvidenceTile(
                    judgment: j,
                    advocateId: it.advocate.id,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => context.push(
            Routes.advocate(it.advocate.id, rec: recommendationId),
          ),
          icon: const Icon(Icons.person_outline),
          label: const Text('Open full profile'),
        ),
        const SizedBox(height: 12),
        Text(
          'Data as of ${formatDate(DateTime(2026, 11, 1))} (demo). Historical outcomes do '
          'not guarantee future results.',
          style: t.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}
