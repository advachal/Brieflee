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
import '../application/judgment_providers.dart';

/// Opens the exact cases behind a number. Every metric in the app is
/// traceable through this sheet.
Future<void> showCaseListSheet(
  BuildContext context, {
  required String title,
  required List<String> judgmentIds,
  String? advocateId,
  String? explanation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 900),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _CaseListBody(
        title: title,
        ids: judgmentIds,
        advocateId: advocateId,
        explanation: explanation,
        scroll: scroll,
      ),
    ),
  );
}

class _CaseListBody extends ConsumerWidget {
  const _CaseListBody({
    required this.title,
    required this.ids,
    required this.scroll,
    this.advocateId,
    this.explanation,
  });

  final String title;
  final List<String> ids;
  final String? advocateId;
  final String? explanation;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cases = ref.watch(judgmentsByIdsProvider(ids.join(',')));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$title (${ids.length})', style: t.titleLarge),
              if (explanation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    explanation!,
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: cases.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No cases in this count',
                    message: 'Nothing matched under the current filters.',
                  )
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => JudgmentEvidenceTile(
                      judgment: list[i],
                      advocateId: advocateId,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// One evidence row: case, citation, court, bench, date, side, outcome, sources.
class JudgmentEvidenceTile extends ConsumerWidget {
  const JudgmentEvidenceTile({
    super.key,
    required this.judgment,
    this.advocateId,
  });
  final Judgment judgment;
  final String? advocateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final j = judgment;
    final a = advocateId == null ? null : j.appearanceOf(advocateId!);
    final bench = j.benchJudgeIds
        .map((id) => ref.watch(judgeNameProvider(id)))
        .join(' & ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(Routes.judgment(j.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(j.title, style: t.titleSmall)),
                  if (a != null) OutcomeBadge(j.disposition.outcomeFor(a.side)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${j.citation} · ${j.caseNumber} · ${formatDate(j.date)}',
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
              Text(
                'Delhi High Court · $bench · ${j.stage.label}',
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (a != null) ...[
                    Pill(
                      label: '${a.side.label} · ${a.role.label}',
                      color: AppColors.navy,
                    ),
                    VerificationBadge(a.verification, compact: true),
                  ],
                  Pill(label: j.disposition.label, color: AppColors.neutral),
                  for (final s in j.sources)
                    SourceBadge(s.type, verification: s.verification),
                  if (j.hasConflict)
                    const Pill(
                      label: 'Source conflict',
                      color: AppColors.unfavorable,
                      icon: Icons.report_gmailerrorred,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
