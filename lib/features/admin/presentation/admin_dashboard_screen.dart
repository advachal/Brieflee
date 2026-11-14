import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../../advocate_search/application/recommendation_providers.dart';
import '../../judgment_viewer/application/judgment_providers.dart';
import '../application/admin_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 28.0;
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: const PageHeader(
              title: 'Admin dashboard',
              subtitle:
                  'Source health, review queues, methodology and audit history',
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Source health'),
              Tab(text: 'Review queues'),
              Tab(text: 'Methodology'),
              Tab(text: 'Audit log'),
            ],
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              children: [
                _SourceHealthTab(),
                _ReviewTab(),
                _MethodologyTab(),
                _AuditTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceHealthTab extends ConsumerWidget {
  const _SourceHealthTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.read(judgmentRepositoryProvider).indexStats();
    return AsyncView<List<SourceHealth>>(
      value: ref.watch(sourceHealthProvider),
      builder: (list) => PageBody(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 200,
                child: MetricTile(
                  label: 'Source references (raw)',
                  value: '${stats.rawRecords}',
                ),
              ),
              SizedBox(
                width: 200,
                child: MetricTile(
                  label: 'Unique cases after dedup',
                  value: '${stats.uniqueCases}',
                ),
              ),
              SizedBox(
                width: 200,
                child: MetricTile(
                  label: 'Live connectors',
                  value: '0 of 3',
                  color: AppColors.mixed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final s in list)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: s.source == SourceType.userUpload
                    ? const IllustrativeTag(label: 'Demo index')
                    : SourceBadge(s.source),
                title: Text(
                  s.status.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: switch (s.status) {
                      ConnectorStatus.healthy => AppColors.favorable,
                      ConnectorStatus.degraded => AppColors.mixed,
                      ConnectorStatus.down => AppColors.unfavorable,
                      ConnectorStatus.notConnected => AppColors.neutral,
                    },
                  ),
                ),
                subtitle: Text(
                  [
                    s.note,
                    if (s.lastSuccess != null)
                      'Last success ${formatDateTime(s.lastSuccess!)}',
                    if (s.brokenLinks > 0) '${s.brokenLinks} broken links',
                  ].join(' · '),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Sources without confirmed, permitted access stay disabled. The '
            'system never circumvents access controls.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ReviewTab extends ConsumerStatefulWidget {
  const _ReviewTab();

  @override
  ConsumerState<_ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends ConsumerState<_ReviewTab> {
  ReviewQueue? _queue;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    final t = Theme.of(context).textTheme;
    return AsyncView<List<ReviewItem>>(
      value: ref.watch(reviewItemsProvider),
      builder: (items) {
        final counts = <ReviewQueue, int>{};
        for (final i in items.where((i) => i.decision == ReviewDecision.open)) {
          counts[i.queue] = (counts[i.queue] ?? 0) + 1;
        }
        final shown = items
            .where((i) => _queue == null || i.queue == _queue)
            .toList();
        return PageBody(
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('All queues'),
                  selected: _queue == null,
                  onSelected: (_) => setState(() => _queue = null),
                ),
                for (final q in ReviewQueue.values)
                  ChoiceChip(
                    label: Text('${q.label} (${counts[q] ?? 0})'),
                    selected: _queue == q,
                    onSelected: (_) => setState(() => _queue = q),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (shown.isEmpty)
              const EmptyState(
                icon: Icons.task_alt,
                title: 'Queue is clear',
                message: 'Nothing waiting for review here.',
              ),
            for (final i in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(i.title, style: t.titleSmall),
                          Pill(label: i.queue.label, color: AppColors.navy),
                          if (i.confidence != null)
                            Pill(
                              label:
                                  'Confidence ${(i.confidence! * 100).round()}%',
                              color: AppColors.mixed,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(i.detail),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (i.relatedJudgmentId != null)
                            OutlinedButton(
                              onPressed: () => context.push(
                                Routes.judgment(i.relatedJudgmentId!),
                              ),
                              child: Text('Open ${i.relatedJudgmentId}'),
                            ),
                          if (i.decision == ReviewDecision.open) ...[
                            FilledButton(
                              onPressed: () =>
                                  _decide(i, ReviewDecision.approved, user),
                              child: const Text('Approve correction'),
                            ),
                            OutlinedButton(
                              onPressed: () =>
                                  _decide(i, ReviewDecision.rejected, user),
                              child: const Text('Reject'),
                            ),
                          ] else
                            Pill(
                              label: i.decision == ReviewDecision.approved
                                  ? 'Approved'
                                  : 'Rejected',
                              color: i.decision == ReviewDecision.approved
                                  ? AppColors.favorable
                                  : AppColors.neutral,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _decide(ReviewItem i, ReviewDecision d, AppUser? user) async {
    await ref
        .read(adminRepositoryProvider)
        .decide(i.id, d, actor: user?.email ?? 'admin');
    ref.invalidate(reviewItemsProvider);
    ref.invalidate(auditLogProvider);
  }
}

class _MethodologyTab extends ConsumerWidget {
  const _MethodologyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(scoringWeightsProvider);
    final ctl = ref.read(scoringWeightsProvider.notifier);
    final user = ref.watch(authControllerProvider);
    final t = Theme.of(context).textTheme;

    Future<void> set(String name, ScoringWeights next) async {
      ctl.update(next);
      await ref
          .read(adminRepositoryProvider)
          .log(
            user?.email ?? 'admin',
            'Methodology weight changed',
            name,
            'Now ${next.methodologyVersion}',
          );
      ref.invalidate(auditLogProvider);
    }

    Widget slider(
      String label,
      double v,
      ScoringWeights Function(double) apply,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${(v * 100).round()}%', style: t.titleSmall),
          ],
        ),
        Slider(
          value: v,
          min: 0,
          max: 0.5,
          divisions: 50,
          onChanged: (x) =>
              ctl.update(apply(double.parse(x.toStringAsFixed(2)))),
          onChangeEnd: (x) =>
              set(label, apply(double.parse(x.toStringAsFixed(2)))),
        ),
      ],
    );

    return PageBody(
      maxWidth: 760,
      children: [
        SectionCard(
          title: 'Scoring weights',
          subtitle:
              'Current version ${w.methodologyVersion} · total ${(w.total * 100).round()}% '
              '(scores are normalised by the total)',
          trailing: TextButton(
            onPressed: ctl.reset,
            child: const Text('Reset to defaults'),
          ),
          child: Column(
            children: [
              slider(
                'Comparable case experience (C)',
                w.comparable,
                (x) => w.copyWith(comparable: x),
              ),
              slider(
                'Court / forum experience (F)',
                w.forum,
                (x) => w.copyWith(forum: x),
              ),
              slider(
                'Judge / bench experience (J)',
                w.judge,
                (x) => w.copyWith(judge: x),
              ),
              slider(
                'Verified outcome evidence (O)',
                w.outcome,
                (x) => w.copyWith(outcome: x),
              ),
              slider(
                'Recency of experience (R)',
                w.recency,
                (x) => w.copyWith(recency: x),
              ),
              slider(
                'Counsel role verification (V)',
                w.roleVerification,
                (x) => w.copyWith(roleVerification: x),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Each change creates a new methodology version so historical '
          'recommendations remain reproducible. Weights are initial proposals, to be '
          'calibrated with reviewed legal data and user testing.',
          style: t.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<AuditEntry>>(
      value: ref.watch(auditLogProvider),
      builder: (list) => PageBody(
        children: [
          Card(
            child: Column(
              children: [
                for (final e in list)
                  ListTile(
                    leading: const Icon(Icons.history, color: AppColors.navy),
                    title: Text('${e.action} · ${e.target}'),
                    subtitle: Text(
                      [
                        e.actor,
                        formatDateTime(e.at),
                        if (e.detail.isNotEmpty) e.detail,
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
