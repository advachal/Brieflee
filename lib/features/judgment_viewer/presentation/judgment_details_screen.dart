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
import '../../admin/application/admin_providers.dart';
import '../../judge_roster/application/roster_providers.dart';
import '../application/judgment_providers.dart';

class JudgmentDetailsScreen extends ConsumerWidget {
  const JudgmentDetailsScreen({super.key, required this.judgmentId});
  final String judgmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(judgmentProvider(judgmentId));
    final data = ref.watch(demoDatasetProvider);
    final t = Theme.of(context).textTheme;

    return AsyncView<Judgment>(
      value: j,
      onRetry: () => ref.invalidate(judgmentProvider(judgmentId)),
      builder: (j) {
        final bench = j.benchJudgeIds
            .map((id) => ref.watch(judgeNameProvider(id)))
            .join(' & ');
        return PageBody(
          maxWidth: 960,
          children: [
            PageHeader(
              title: j.title,
              subtitle: '${j.citation} · ${formatDate(j.date)}',
              leading: context.canPop()
                  ? IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                    )
                  : null,
              actions: [
                const IllustrativeTag(label: 'Fictional judgment'),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(adminRepositoryProvider)
                        .report(
                          title: 'User report on ${j.citation}',
                          detail: 'Reported from the judgment view.',
                          judgmentId: j.id,
                        );
                    ref.invalidate(reviewItemsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Reported. A reviewer will check this record.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Report an error'),
                ),
              ],
            ),
            if (j.hasConflict)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.unfavorable.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.unfavorable.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.report_gmailerrorred,
                      color: AppColors.unfavorable,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(j.conflictNote!)),
                  ],
                ),
              ),
            SectionCard(
              title: 'Case metadata',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValueRow('Case name', j.title),
                  KeyValueRow('Citation', j.citation),
                  KeyValueRow('Case number', j.caseNumber),
                  KeyValueRow('Court', 'Delhi High Court'),
                  KeyValueRow('Judge / bench', bench),
                  KeyValueRow('Date', formatDate(j.date)),
                  KeyValueRow('Case type', j.category),
                  KeyValueRow('Stage', j.stage.label),
                  KeyValueRow('Statutes', j.statutes.join('; ')),
                  KeyValueRow('Summary', j.summary),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Outcome classification',
              subtitle: 'Linked to the supporting passage below',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValueRow('Disposition', j.disposition.label),
                  KeyValueRow(
                    'Counts toward outcome rate',
                    j.disposition.eligible ? 'Yes' : 'No (excluded)',
                  ),
                  KeyValueRow(
                    'Confidence',
                    '${(j.dispositionConfidence * 100).round()}%',
                  ),
                  KeyValueRow(
                    'Review status',
                    '',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(
                        label: j.reviewStatus.label,
                        color: j.reviewStatus == ReviewStatus.awaitingReview
                            ? AppColors.mixed
                            : AppColors.favorable,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Counsel appearances',
              child: Column(
                children: [
                  for (final a in j.appearances)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.navy,
                        child: Text(
                          data.advocate(a.advocateId)?.initials ?? '?',
                          style: const TextStyle(color: AppColors.gold),
                        ),
                      ),
                      title: Text(
                        data.advocate(a.advocateId)?.displayName ??
                            a.advocateId,
                      ),
                      subtitle: Text(
                        '${a.side.label} · ${a.role.label} · '
                        'confidence ${(a.confidence * 100).round()}%',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          if (j.disposition.eligible)
                            OutcomeBadge(j.disposition.outcomeFor(a.side)),
                          VerificationBadge(a.verification, compact: true),
                        ],
                      ),
                      onTap: () => context.push(Routes.advocate(a.advocateId)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Relevant passages',
              subtitle:
                  'Every classification points to the text that supports it',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in j.passages)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.offWhite,
                        borderRadius: BorderRadius.circular(10),
                        border: const Border(
                          left: BorderSide(color: AppColors.gold, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.paragraph,
                            style: t.labelLarge?.copyWith(
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            p.text,
                            style: t.bodyMedium?.copyWith(height: 1.5),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Supports: ${p.supports}',
                            style: t.bodySmall?.copyWith(color: AppColors.teal),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Sources',
              subtitle:
                  'Found in ${j.sources.length} source${j.sources.length == 1 ? '' : 's'}; '
                  'counted once after deduplication',
              child: Column(
                children: [
                  for (final s in j.sources)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SourceBadge(s.type),
                      title: Text(s.type.role),
                      subtitle: Text(
                        'Retrieved ${formatDate(s.retrievedAt)} · document ${s.documentVersion}'
                        ' · ${s.externalId ?? ''}',
                      ),
                      trailing: Tooltip(
                        message: 'Demo record: no live source link',
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open source'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
