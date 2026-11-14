import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/models.dart';
import '../../../../core/widgets/status_badges.dart';
import '../../../judgment_viewer/presentation/case_list_sheet.dart';
import 'evidence_panel.dart';

class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.item,
    required this.rank,
    required this.recommendationId,
    required this.selected,
    required this.comparing,
    required this.shortlisted,
    required this.onSelect,
    required this.onToggleCompare,
    required this.onToggleShortlist,
    required this.expandable,
  });

  final RecommendationItem item;
  final int? rank;
  final String recommendationId;
  final bool selected;
  final bool comparing;
  final bool shortlisted;
  final VoidCallback onSelect;
  final VoidCallback onToggleCompare;
  final VoidCallback onToggleShortlist;

  /// Phone layout: evidence expands inside the card.
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = item.metrics;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: item.insufficient
              ? AppColors.border
              : AppColors.navy,
          child: Text(
            rank == null ? '–' : '$rank',
            style: TextStyle(
              color: item.insufficient ? AppColors.muted : AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(item.advocate.displayName, style: t.titleMedium),
                  const IllustrativeTag(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.headline,
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (!item.insufficient)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.score.round()}%',
                style: t.titleLarge?.copyWith(color: AppColors.teal),
              ),
              Text(
                'match',
                style: t.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
      ],
    );

    void open(String title, List<String> ids) => showCaseListSheet(
      context,
      title: title,
      judgmentIds: ids,
      advocateId: item.advocate.id,
    );

    final stats = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ActionChip(
          avatar: const Icon(Icons.menu_book_outlined, size: 16),
          label: Text('${m.comparableIds.length} relevant'),
          onPressed: () => open('Comparable cases', m.comparableIds),
        ),
        ActionChip(
          avatar: const Icon(
            Icons.thumb_up_alt_outlined,
            size: 16,
            color: AppColors.favorable,
          ),
          label: Text(
            '${m.favorableIds.length}/${m.eligibleIds.length} favorable',
          ),
          onPressed: () => open('Favorable outcomes', m.favorableIds),
        ),
        if (item.components.judgeApplied)
          ActionChip(
            avatar: const Icon(Icons.gavel, size: 16),
            label: Text('${m.judgeIds.length} before bench'),
            onPressed: () =>
                open('Matters before the identified bench', m.judgeIds),
          ),
        ReliabilityBadge(item.reliability),
      ],
    );

    final actions = Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: onToggleCompare,
          icon: Icon(
            comparing ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
          ),
          label: const Text('Compare'),
        ),
        TextButton.icon(
          onPressed: onToggleShortlist,
          icon: Icon(
            shortlisted ? Icons.bookmark : Icons.bookmark_border,
            size: 18,
          ),
          label: Text(shortlisted ? 'Shortlisted' : 'Shortlist'),
        ),
        TextButton.icon(
          onPressed: () => context.push(
            Routes.advocate(item.advocate.id, rec: recommendationId),
          ),
          icon: const Icon(Icons.person_outline, size: 18),
          label: const Text('Profile'),
        ),
      ],
    );

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          stats,
          const SizedBox(height: 4),
          actions,
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.teal : AppColors.border,
          width: selected ? 1.8 : 1,
        ),
      ),
      child: expandable
          ? Column(
              children: [
                body,
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      'Why this advocate? Evidence & methodology',
                      style: t.labelLarge?.copyWith(color: AppColors.teal),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final r in [...item.reasons, ...item.limitations])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $r', style: t.bodySmall),
                        ),
                      const SizedBox(height: 10),
                      TraceableMetrics(item: item),
                      const SizedBox(height: 12),
                      ScoreBreakdown(item: item),
                    ],
                  ),
                ),
              ],
            )
          : InkWell(onTap: onSelect, child: body),
    );
  }
}
