import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/mock/demo_dataset.dart';
import '../../../../core/models/models.dart';
import '../../../court_explorer/application/court_providers.dart';
import '../../../judge_roster/application/roster_providers.dart';
import '../../application/recommendation_providers.dart';

/// Advanced filters. Changes re-score the same evidence set immediately.
class FiltersPanel extends ConsumerWidget {
  const FiltersPanel({super.key, required this.recommendationId, this.scroll});
  final String recommendationId;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(resultFiltersProvider(recommendationId));
    final ctl = ref.read(resultFiltersProvider(recommendationId).notifier);
    final ctx = ref
        .read(recommendationRepositoryProvider)
        .contextFor(recommendationId);
    final courts = ref.watch(courtsProvider);
    final judges = ref.watch(judgesProvider(f.courtId ?? 'dhc'));
    final t = Theme.of(context).textTheme;
    final cats = f.categories.isEmpty && ctx != null
        ? {ctx.category}
        : f.categories;

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.labelLarge?.copyWith(color: AppColors.navy)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Text('Filters', style: t.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () => ctl.set(SearchFilters(courtId: ctx?.courtId)),
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        section(
          'Court or tribunal',
          courts.when(
            data: (list) => DropdownButtonFormField<String?>(
              isExpanded: true,
              key: ValueKey('court-${f.courtId}'),
              initialValue: f.courtId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All supported courts'),
                ),
                for (final c in list.where(
                  (c) => c.support == CourtSupport.pilot,
                ))
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) =>
                  ctl.set(f.copyWith(courtId: v, clearCourt: v == null)),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ),
        section(
          'Case type',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in DemoCategories.all)
                FilterChip(
                  label: Text(c, style: const TextStyle(fontSize: 12)),
                  selected: cats.contains(c),
                  onSelected: (on) {
                    final next = {...cats};
                    on ? next.add(c) : next.remove(c);
                    if (next.isEmpty) return;
                    ctl.set(f.copyWith(categories: next));
                  },
                ),
            ],
          ),
        ),
        section(
          'Case stage',
          DropdownButtonFormField<CaseStage?>(
            isExpanded: true,
            key: ValueKey('stage-${f.stage}'),
            initialValue: f.stage,
            items: [
              const DropdownMenuItem(value: null, child: Text('Any stage')),
              for (final s in CaseStage.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) =>
                ctl.set(f.copyWith(stage: v, clearStage: v == null)),
          ),
        ),
        section(
          'Representation side',
          RadioGroup<SideFilter>(
            groupValue: f.side,
            onChanged: (v) => ctl.set(f.copyWith(side: v)),
            child: Column(
              children: [
                for (final s in SideFilter.values)
                  RadioListTile<SideFilter>(
                    value: s,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        section(
          'Judge / bench',
          judges.when(
            data: (list) => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final j in list)
                  FilterChip(
                    label: Text(
                      j.name.replaceFirst('Justice ', ''),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: f.judgeIds.contains(j.id),
                    onSelected: (on) {
                      final next = {...f.judgeIds};
                      on ? next.add(j.id) : next.remove(j.id);
                      ctl.set(f.copyWith(judgeIds: next));
                    },
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),
        section(
          'Time range: last ${f.yearsBack} years',
          Slider(
            value: f.yearsBack.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            label: '${f.yearsBack} years',
            onChanged: (v) => ctl.set(f.copyWith(yearsBack: v.round())),
          ),
        ),
        section(
          'Minimum verified comparable cases: ${f.minVerifiedComparable}',
          Slider(
            value: f.minVerifiedComparable.toDouble(),
            min: 1,
            max: 12,
            divisions: 11,
            label: '${f.minVerifiedComparable}',
            onChanged: (v) =>
                ctl.set(f.copyWith(minVerifiedComparable: v.round())),
          ),
        ),
        Text(
          'Advocates below the minimum are listed separately as having '
          'insufficient verified evidence, not ranked.',
          style: t.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}
