import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';
import '../../court_explorer/application/court_providers.dart';
import '../application/roster_providers.dart';

class JudgeExplorerScreen extends ConsumerWidget {
  const JudgeExplorerScreen({
    super.key,
    required this.courtId,
    this.initialTab,
  });
  final String courtId;
  final String? initialTab;

  static const _tabs = [
    'directory',
    'roster',
    'causelist',
    'notices',
    'history',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final court = ref.watch(courtProvider(courtId));
    final pad = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 28.0;
    final idx = _tabs.indexOf(initialTab ?? '');

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: idx < 0 ? 0 : idx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: PageHeader(
              title: 'Judge explorer',
              subtitle: court.when(
                data: (c) => '${c.name} · current roster, benches and history',
                loading: () => 'Loading court…',
                error: (_, _) => 'Court unavailable',
              ),
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Judge directory'),
              Tab(text: 'Roster'),
              Tab(text: 'Cause list'),
              Tab(text: 'Sitting notices'),
              Tab(text: 'History'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                _Directory(courtId: courtId),
                _RosterTab(courtId: courtId),
                _CauseList(courtId: courtId),
                _Notices(courtId: courtId),
                _History(courtId: courtId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Directory extends ConsumerWidget {
  const _Directory({required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<Judge>>(
      value: ref.watch(judgesProvider(courtId)),
      builder: (judges) => PageBody(
        children: [
          const _Explainer(
            'Judges currently serving at this court. A judge missing from a '
            'single list is marked unverified, never assumed absent.',
          ),
          for (final j in judges)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.navy,
                  child: Icon(Icons.gavel, color: AppColors.gold, size: 18),
                ),
                title: Text(j.name),
                subtitle: Text(
                  j.isSitting
                      ? j.designation
                      : '${j.designation} · not in current roster',
                ),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    const IllustrativeTag(),
                    VerificationBadge(j.verification, compact: true),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RosterTab extends ConsumerWidget {
  const _RosterTab({required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<CourtRoster?>(
      value: ref.watch(rosterProvider(courtId)),
      builder: (r) {
        if (r == null) {
          return const EmptyState(
            icon: Icons.event_busy,
            title: 'No roster',
            message: 'No verified roster is available for this court yet.',
          );
        }
        return PageBody(
          children: [
            _RosterMeta(version: r.current),
            const SizedBox(height: 14),
            for (final a in r.current.assignments) _AssignmentCard(a: a),
          ],
        );
      },
    );
  }
}

class _RosterMeta extends StatelessWidget {
  const _RosterMeta({required this.version});
  final RosterVersion version;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: version.label,
    trailing: VerificationBadge(version.verification),
    child: Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        Text('Effective ${formatDate(version.effectiveFrom)}'),
        Text(
          'Source: ${version.sourceLabel}',
          style: const TextStyle(color: AppColors.muted),
        ),
        Text(
          'Last successful check: ${formatDateTime(version.lastCheckedAt)}',
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _AssignmentCard extends ConsumerWidget {
  const _AssignmentCard({required this.a});
  final BenchAssignment a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = a.judgeIds
        .map((id) => ref.watch(judgeNameProvider(id)))
        .join(' & ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.tealSoft,
          child: Text(
            a.isDivisionBench ? 'DB' : 'SB',
            style: const TextStyle(
              color: AppColors.teal,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(names),
        subtitle: Text('${a.courtRoom} · ${a.subjects.join(', ')}'),
        trailing: Text(
          a.effectiveTo == null
              ? 'from ${formatDate(a.effectiveFrom)}'
              : '${formatDate(a.effectiveFrom)} – ${formatDate(a.effectiveTo!)}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    );
  }
}

class _CauseList extends ConsumerWidget {
  const _CauseList({required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<CaseListing>>(
      value: ref.watch(causeListProvider(courtId)),
      builder: (list) => PageBody(
        children: [
          const _Explainer(
            'Cases scheduled before particular benches on specific dates '
            '(demo entries). Unverified entries are shown as such.',
          ),
          for (final l in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.caseNumber,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Pill(
                          label: l.status.label,
                          color: l.status == ListingStatus.benchChanged
                              ? AppColors.mixed
                              : AppColors.navy,
                        ),
                        VerificationBadge(l.verification, compact: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDate(l.listingDate)} · ${l.courtRoom} · Item ${l.itemNumber} · '
                      '${l.benchJudgeIds.map((id) => ref.watch(judgeNameProvider(id))).join(' & ')}',
                    ),
                    Text(
                      '${l.causeListLabel} · checked ${relativeTime(l.lastCheckedAt)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Notices extends ConsumerWidget {
  const _Notices({required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<SittingNotice>>(
      value: ref.watch(sittingNoticesProvider(courtId)),
      builder: (list) => PageBody(
        children: [
          const _Explainer(
            'Changes, cancellations or substitutions affecting scheduled sittings.',
          ),
          if (list.isEmpty)
            const EmptyState(
              icon: Icons.event_available,
              title: 'No notices',
              message: 'No sitting notices on record.',
            ),
          for (final n in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(
                  Icons.campaign_outlined,
                  color: AppColors.navy,
                ),
                title: Text(formatDate(n.date)),
                subtitle: Text(n.description),
                trailing: VerificationBadge(n.verification, compact: true),
              ),
            ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<CourtRoster?>(
      value: ref.watch(rosterProvider(courtId)),
      builder: (r) {
        if (r == null) return const SizedBox.shrink();
        final prev = r.history.isEmpty ? null : r.history.first;
        String names(List<String> ids) =>
            ids.map((id) => ref.watch(judgeNameProvider(id))).join(' & ');
        final changes = <(String, String, String)>[];
        if (prev != null) {
          for (final a in r.current.assignments) {
            final old = prev.assignments.where((x) => x.benchId == a.benchId);
            final before = old.isEmpty
                ? '— (new bench)'
                : names(old.first.judgeIds);
            final after = names(a.judgeIds);
            if (before != after) {
              changes.add((
                '${a.courtRoom}: ${a.subjects.first}',
                before,
                after,
              ));
            }
          }
        }
        return PageBody(
          children: [
            const _Explainer(
              'Earlier assignments are preserved. Experience before a judge '
              'remains relevant after a roster change.',
            ),
            if (prev != null)
              SectionCard(
                title: 'Changes from ${prev.label} to ${r.current.label}',
                child: Column(
                  children: [
                    for (final c in changes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.swap_horiz,
                          color: AppColors.mixed,
                        ),
                        title: Text(c.$1),
                        subtitle: Text('${c.$2}  →  ${c.$3}'),
                      ),
                    if (changes.isEmpty) const Text('No assignment changes.'),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            for (final v in r.history) ...[
              _RosterMeta(version: v),
              const SizedBox(height: 8),
              for (final a in v.assignments) _AssignmentCard(a: a),
            ],
          ],
        );
      },
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppColors.muted)),
        ),
      ],
    ),
  );
}
