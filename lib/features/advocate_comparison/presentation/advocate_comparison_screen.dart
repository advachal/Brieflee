import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../../advocate_search/application/recommendation_providers.dart';
import '../../judgment_viewer/presentation/case_list_sheet.dart';
import '../application/comparison_providers.dart';

class AdvocateComparisonScreen extends ConsumerStatefulWidget {
  const AdvocateComparisonScreen({
    super.key,
    this.recommendationId,
    this.advocateIds = const [],
  });
  final String? recommendationId;
  final List<String> advocateIds;

  @override
  ConsumerState<AdvocateComparisonScreen> createState() =>
      _AdvocateComparisonScreenState();
}

class _AdvocateComparisonScreenState
    extends ConsumerState<AdvocateComparisonScreen> {
  String get _recId => widget.recommendationId ?? 'rec-demo-1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.advocateIds.isNotEmpty) {
        ref
            .read(comparisonSelectionProvider.notifier)
            .setAll(widget.advocateIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final recAsync = ref.watch(recommendationProvider(_recId));
    final selected = ref.watch(comparisonSelectionProvider);
    final t = Theme.of(context).textTheme;

    return AsyncView<Recommendation>(
      value: recAsync,
      builder: (rec) {
        final all = [...rec.ranked, ...rec.insufficient];
        final items = [
          for (final id in selected)
            for (final i in all)
              if (i.advocate.id == id) i,
        ];
        return PageBody(
          children: [
            PageHeader(
              title: 'Compare advocates',
              subtitle: widget.recommendationId == null
                  ? 'Using the demo matter (trademark interim injunction, Delhi High Court)'
                  : 'Same matter, filters and methodology (${rec.methodologyVersion})',
            ),
            Text('Choose up to three', style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final i in all)
                  FilterChip(
                    label: Text(i.advocate.displayName),
                    selected: selected.contains(i.advocate.id),
                    onSelected: (_) => ref
                        .read(comparisonSelectionProvider.notifier)
                        .toggle(i.advocate.id),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (items.length < 2)
              const EmptyState(
                icon: Icons.compare_arrows,
                title: 'Pick at least two advocates',
                message: 'Select advocates above to see their evidence side by side.',
              )
            else
              _ComparisonTable(items: items, recId: _recId),
            const SizedBox(height: 12),
            Text(
              'Larger samples are not automatically better or worse: compare eligible '
              'outcomes, excluded matters and evidence reliability together.',
              style: t.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        );
      },
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.items, required this.recId});
  final List<RecommendationItem> items;
  final String recId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    Widget count(
      RecommendationItem it,
      String title,
      List<String> ids, {
      Color? color,
    }) => TextButton(
      onPressed: () => showCaseListSheet(
        context,
        title: '$title · ${it.advocate.displayName}',
        judgmentIds: ids,
        advocateId: it.advocate.id,
      ),
      style: TextButton.styleFrom(
        foregroundColor: color ?? AppColors.navy,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
      ),
      child: Text(
        '${ids.length}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    final rows = <(String, Widget Function(RecommendationItem))>[
      (
        'Match',
        (it) => Text(
          it.insufficient ? 'Not ranked' : '${it.score.round()}%',
          style: t.titleMedium?.copyWith(color: AppColors.teal),
        ),
      ),
      ('Evidence reliability', (it) => ReliabilityBadge(it.reliability)),
      (
        'Comparable cases',
        (it) => count(it, 'Comparable', it.metrics.comparableIds),
      ),
      (
        'Verified appearances',
        (it) => count(it, 'Verified', it.metrics.verifiedAppearanceIds),
      ),
      (
        'Eligible outcomes',
        (it) => count(it, 'Eligible', it.metrics.eligibleIds),
      ),
      (
        'Favorable',
        (it) => count(
          it,
          'Favorable',
          it.metrics.favorableIds,
          color: AppColors.favorable,
        ),
      ),
      (
        'Unfavorable',
        (it) => count(
          it,
          'Unfavorable',
          it.metrics.unfavorableIds,
          color: AppColors.unfavorable,
        ),
      ),
      (
        'Mixed',
        (it) => count(it, 'Mixed', it.metrics.mixedIds, color: AppColors.mixed),
      ),
      (
        'Excluded from rate',
        (it) => count(
          it,
          'Excluded',
          it.metrics.excludedIds,
          color: AppColors.neutral,
        ),
      ),
      (
        'Raw favorable rate',
        (it) => Text(formatPercent(it.metrics.favorableRate)),
      ),
      ('Same forum', (it) => count(it, 'Same forum', it.metrics.forumIds)),
      (
        'Before identified bench',
        (it) => it.components.judgeApplied
            ? count(it, 'Before bench', it.metrics.judgeIds)
            : const Text('—'),
      ),
      (
        'Search hits (not appearances)',
        (it) => Text('${it.metrics.searchHits}'),
      ),
      ('Comparable experience', (it) => _bar(it.components.comparable)),
      ('Forum experience', (it) => _bar(it.components.forum)),
      (
        'Bench experience',
        (it) => it.components.judgeApplied
            ? _bar(it.components.judge)
            : const Text('—'),
      ),
      ('Outcome evidence', (it) => _bar(it.components.outcome)),
      ('Recency', (it) => _bar(it.components.recency)),
      ('Role verification', (it) => _bar(it.components.roleVerification)),
      (
        'Limitations',
        (it) => Text(
          it.limitations.isEmpty ? 'None noted' : it.limitations.join('\n'),
          style: t.bodySmall,
        ),
      ),
    ];

    const labelW = 190.0;

    return LayoutBuilder(
      builder: (context, box) {
        final colW = ((box.maxWidth - labelW - 2) / items.length).clamp(
          220.0,
          420.0,
        );
        return Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: labelW + colW * items.length,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    color: AppColors.navy,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: labelW - 14),
                        for (final it in items)
                          SizedBox(
                            width: colW,
                            child: InkWell(
                              onTap: () => context.push(
                                Routes.advocate(it.advocate.id, rec: recId),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.advocate.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    it.advocate.chamber,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var r = 0; r < rows.length; r++)
                    Container(
                      color: r.isEven ? AppColors.surface : AppColors.offWhite,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: labelW - 14,
                            child: Text(
                              rows[r].$1,
                              style: t.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          for (final it in items)
                            SizedBox(
                              width: colW,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: rows[r].$2(it),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _bar(double v) => Row(
    children: [
      SizedBox(
        width: 120,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v.clamp(0, 1),
            minHeight: 6,
            color: AppColors.teal,
            backgroundColor: AppColors.border,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${(v * 100).round()}', style: const TextStyle(fontSize: 12)),
    ],
  );
}
