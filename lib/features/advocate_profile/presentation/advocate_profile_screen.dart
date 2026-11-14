import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../admin/application/admin_providers.dart';
import '../../advocate_search/application/recommendation_providers.dart';
import '../../advocate_search/presentation/widgets/evidence_panel.dart';
import '../../judge_roster/application/roster_providers.dart';
import '../../judgment_viewer/presentation/case_list_sheet.dart';
import '../application/advocate_providers.dart';

class AdvocateProfileScreen extends ConsumerStatefulWidget {
  const AdvocateProfileScreen({
    super.key,
    required this.advocateId,
    this.recommendationId,
  });
  final String advocateId;
  final String? recommendationId;

  @override
  ConsumerState<AdvocateProfileScreen> createState() =>
      _AdvocateProfileScreenState();
}

class _AdvocateProfileScreenState extends ConsumerState<AdvocateProfileScreen> {
  String? _category;
  PartyOutcome? _outcome;
  bool _verifiedOnly = false;

  Future<void> _report(Advocate a) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Report an error in ${a.displayName}\'s profile'),
        content: TextField(
          controller: c,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'What looks wrong? e.g. wrong side, duplicate identity, missing case',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send report'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await ref
          .read(adminRepositoryProvider)
          .report(
            title: 'User report: ${a.displayName}',
            detail: c.text.trim(),
          );
      ref.invalidate(reviewItemsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Thanks. The report is in the data-quality review queue.',
            ),
          ),
        );
      }
    }
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adv = ref.watch(advocateProvider(widget.advocateId));
    final cases = ref.watch(advocateCasesProvider(widget.advocateId));
    final recId = widget.recommendationId;
    final rec = recId == null
        ? null
        : ref.watch(recommendationProvider(recId)).value;
    RecommendationItem? item;
    if (rec != null) {
      for (final i in [...rec.ranked, ...rec.insufficient]) {
        if (i.advocate.id == widget.advocateId) item = i;
      }
    }
    final t = Theme.of(context).textTheme;

    return AsyncView<Advocate>(
      value: adv,
      onRetry: () => ref.invalidate(advocateProvider(widget.advocateId)),
      builder: (a) => PageBody(
        children: [
          PageHeader(
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.navy,
              child: Text(
                a.initials,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: a.displayName,
            subtitle: '${a.chamber} · practising since ${a.practiceSince}',
            actions: [
              const IllustrativeTag(label: 'Fictional advocate'),
              VerificationBadge(a.identityVerification),
              OutlinedButton.icon(
                onPressed: () =>
                    context.push(Routes.compare(rec: recId, ids: [a.id])),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare'),
              ),
              OutlinedButton.icon(
                onPressed: () => _report(a),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report an error'),
              ),
            ],
          ),
          SectionCard(
            title: 'Identity',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValueRow('Known aliases', a.aliases.join(' · ')),
                KeyValueRow('Practice areas', a.practiceAreas.join(', ')),
                KeyValueRow('Identity status', a.identityVerification.label),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (item != null) ...[
            SectionCard(
              title: 'Match for this matter',
              subtitle: item.headline,
              trailing: Pill(
                label: '${item.score.round()}%',
                color: AppColors.teal,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TraceableMetrics(
                    item: item,
                    columns: MediaQuery.sizeOf(context).width > 900 ? 3 : 2,
                  ),
                  const SizedBox(height: 14),
                  ScoreBreakdown(item: item),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          cases.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e),
            data: (all) {
              final verified = all
                  .where((j) => j.appearanceOf(a.id)!.isVerified)
                  .toList();
              final byOutcome = <PartyOutcome, List<Judgment>>{};
              for (final j in verified) {
                final o = j.disposition.eligible
                    ? j.outcomeFor(a.id)
                    : PartyOutcome.excluded;
                byOutcome.putIfAbsent(o, () => []).add(j);
              }
              final byCat = <String, int>{};
              for (final j in all) {
                byCat[j.category] = (byCat[j.category] ?? 0) + 1;
              }
              final byJudge = <String, List<String>>{};
              for (final j in verified) {
                for (final jid in j.benchJudgeIds) {
                  byJudge.putIfAbsent(jid, () => []).add(j.id);
                }
              }
              final filtered = all.where((j) {
                if (_category != null && j.category != _category) return false;
                if (_verifiedOnly && !j.appearanceOf(a.id)!.isVerified) {
                  return false;
                }
                if (_outcome != null) {
                  final o = j.disposition.eligible
                      ? j.outcomeFor(a.id)
                      : PartyOutcome.excluded;
                  if (o != _outcome) return false;
                }
                return true;
              }).toList();
              final mentions = ref
                  .read(advocateRepositoryProvider)
                  .mentionOnlyCount(a.id);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: 'All-time record (demo index)',
                    subtitle: 'Search hits, appearances and judgments are counted separately.',
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth > 700 ? 4 : 2;
                        final w = (c.maxWidth - 8 * (cols - 1)) / cols;
                        void open(String title, List<Judgment> js) =>
                            showCaseListSheet(
                              context,
                              title: title,
                              judgmentIds: js.map((j) => j.id).toList(),
                              advocateId: a.id,
                            );
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Search hits',
                                value: '${all.length + mentions}',
                                hint: '$mentions mention-only',
                                color: AppColors.neutral,
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Recorded appearances',
                                value: '${all.length}',
                                onTap: () => open('Recorded appearances', all),
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Verified appearances',
                                value: '${verified.length}',
                                onTap: () =>
                                    open('Verified appearances', verified),
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Favorable (verified, eligible)',
                                value:
                                    '${byOutcome[PartyOutcome.favorable]?.length ?? 0}',
                                color: AppColors.favorable,
                                onTap: () => open(
                                  'Favorable',
                                  byOutcome[PartyOutcome.favorable] ?? [],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Unfavorable',
                                value:
                                    '${byOutcome[PartyOutcome.unfavorable]?.length ?? 0}',
                                color: AppColors.unfavorable,
                                onTap: () => open(
                                  'Unfavorable',
                                  byOutcome[PartyOutcome.unfavorable] ?? [],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Mixed',
                                value:
                                    '${byOutcome[PartyOutcome.mixed]?.length ?? 0}',
                                color: AppColors.mixed,
                                onTap: () => open(
                                  'Mixed',
                                  byOutcome[PartyOutcome.mixed] ?? [],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: MetricTile(
                                label: 'Excluded / indeterminate',
                                value:
                                    '${byOutcome[PartyOutcome.excluded]?.length ?? 0}',
                                color: AppColors.neutral,
                                onTap: () => open(
                                  'Excluded',
                                  byOutcome[PartyOutcome.excluded] ?? [],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, c) {
                      final expertise = SectionCard(
                        title: 'Expertise by case type',
                        child: Column(
                          children: [
                            for (final e
                                in (byCat.entries.toList()
                                  ..sort((x, y) => y.value - x.value)))
                              ComponentBar(
                                label: e.key,
                                value: e.value / all.length,
                                weight: e.value / all.length,
                              ),
                          ],
                        ),
                      );
                      final judges = SectionCard(
                        title: 'Experience before judges',
                        subtitle: 'Documented appearances only, not influence or relationships.',
                        child: Column(
                          children: [
                            for (final e
                                in (byJudge.entries.toList()..sort(
                                  (x, y) => y.value.length - x.value.length,
                                )))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  ref.watch(judgeNameProvider(e.key)),
                                ),
                                trailing: TextButton(
                                  onPressed: () => showCaseListSheet(
                                    context,
                                    title:
                                        'Before ${ref.read(judgeNameProvider(e.key))}',
                                    judgmentIds: e.value,
                                    advocateId: a.id,
                                  ),
                                  child: Text('${e.value.length} cases'),
                                ),
                              ),
                          ],
                        ),
                      );
                      if (c.maxWidth < 760) {
                        return Column(
                          children: [
                            expertise,
                            const SizedBox(height: 14),
                            judges,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: expertise),
                          const SizedBox(width: 14),
                          Expanded(child: judges),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Case history (${filtered.length})',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            DropdownButton<String?>(
                              value: _category,
                              hint: const Text('All case types'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All case types'),
                                ),
                                for (final c in DemoCategories.all)
                                  DropdownMenuItem(value: c, child: Text(c)),
                              ],
                              onChanged: (v) => setState(() => _category = v),
                            ),
                            DropdownButton<PartyOutcome?>(
                              value: _outcome,
                              hint: const Text('Any outcome'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Any outcome'),
                                ),
                                for (final o in PartyOutcome.values)
                                  DropdownMenuItem(
                                    value: o,
                                    child: Text(o.label),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _outcome = v),
                            ),
                            FilterChip(
                              label: const Text('Verified only'),
                              selected: _verifiedOnly,
                              onSelected: (v) =>
                                  setState(() => _verifiedOnly = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (filtered.isEmpty)
                          Text(
                            'No cases match these filters.',
                            style: t.bodyMedium,
                          ),
                        for (final j in filtered.take(40))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: JudgmentEvidenceTile(
                              judgment: j,
                              advocateId: a.id,
                            ),
                          ),
                        if (filtered.length > 40)
                          Text(
                            'Showing 40 of ${filtered.length}.',
                            style: t.bodySmall?.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
