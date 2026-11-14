import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/api/brieflee_api.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/constants/breakpoints.dart';
import '../../../shared/utilities/formatters.dart';
import '../../case_intake/application/matter_providers.dart';
import '../../judge_roster/application/roster_providers.dart';
import '../../notifications/application/alert_providers.dart';
import '../application/recommendation_providers.dart';
import 'widgets/evidence_panel.dart';
import 'widgets/filters_panel.dart';
import 'widgets/result_card.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, required this.recommendationId});
  final String recommendationId;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final Set<String> _compare = {};

  String get _id => widget.recommendationId;

  void _toggleCompare(String id) {
    setState(() {
      if (_compare.contains(id)) {
        _compare.remove(id);
      } else if (_compare.length < 3) {
        _compare.add(id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compare up to three advocates at a time.'),
          ),
        );
      }
    });
  }

  Future<void> _toggleShortlist(Matter matter, String advocateId) async {
    final list = [...matter.shortlist];
    list.contains(advocateId) ? list.remove(advocateId) : list.add(advocateId);
    await ref.read(matterRepositoryProvider).updateShortlist(matter.id, list);
    refreshMatters(ref, matter.id);
  }

  Future<void> _monitor(Matter matter) async {
    await ref
        .read(alertRepositoryProvider)
        .create(
          CreateAlertRequest(
            label: matter.title,
            kinds: {
              AlertKind.benchChange,
              AlertKind.listingChange,
              AlertKind.newJudgment,
              AlertKind.recommendationUpdated,
            },
            matterId: matter.id,
          ),
        );
    await ref.read(matterRepositoryProvider).setMonitored(matter.id, true);
    refreshMatters(ref, matter.id);
    ref.invalidate(alertSubscriptionsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Monitoring on. You will be alerted to verified bench, '
            'listing and judgment changes.',
          ),
        ),
      );
    }
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(
          children: [
            Expanded(
              child: FiltersPanel(recommendationId: _id, scroll: scroll),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Show results'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recAsync = ref.watch(recommendationProvider(_id));
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.wide;
    final compact = width < Breakpoints.compact;

    final rec = recAsync.value;
    if (rec == null) {
      return recAsync.hasError
          ? ErrorView(
              error: recAsync.error!,
              onRetry: () => ref.invalidate(recommendationProvider(_id)),
            )
          : const LoadingView(label: 'Scoring advocates…');
    }

    final matter = ref.watch(matterProvider(rec.matterId)).value;
    final selectedId = ref.watch(selectedAdvocateProvider(_id));
    final allItems = [...rec.ranked, ...rec.insufficient];
    RecommendationItem? selected;
    for (final i in allItems) {
      if (i.advocate.id == selectedId) selected = i;
    }
    selected ??= rec.ranked.isNotEmpty ? rec.ranked.first : null;

    Widget card(RecommendationItem it, int? rank) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ResultCard(
        item: it,
        rank: rank,
        recommendationId: _id,
        selected: wide && selected?.advocate.id == it.advocate.id,
        comparing: _compare.contains(it.advocate.id),
        shortlisted: matter?.shortlist.contains(it.advocate.id) ?? false,
        expandable: !wide,
        onSelect: () => ref
            .read(selectedAdvocateProvider(_id).notifier)
            .select(it.advocate.id),
        onToggleCompare: () => _toggleCompare(it.advocate.id),
        onToggleShortlist: matter == null
            ? () {}
            : () => _toggleShortlist(matter, it.advocate.id),
      ),
    );

    final results = ListView(
      padding: EdgeInsets.all(compact ? 16 : 22),
      children: [
        _ResultsHeader(
          rec: rec,
          matter: matter,
          compareCount: _compare.length,
          onCompare: _compare.length < 2
              ? null
              : () => context.push(
                  Routes.compare(rec: _id, ids: _compare.toList()),
                ),
          onFilters: wide ? null : _openFilters,
          onMonitor: matter == null || matter.monitored
              ? null
              : () => _monitor(matter),
        ),
        if (recAsync.isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(
              color: AppColors.teal,
              backgroundColor: AppColors.border,
            ),
          ),
        if (rec.ranked.isEmpty)
          const EmptyState(
            icon: Icons.person_search,
            title: 'No advocate meets the evidence threshold',
            message:
                'We would rather say so than force a ranking. Try widening the '
                'time range, case types or lowering the minimum verified cases.',
          ),
        for (var i = 0; i < rec.ranked.length; i++) card(rec.ranked[i], i + 1),
        if (rec.insufficient.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Insufficient verified evidence to recommend confidently',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'These advocates appear in comparable matters, but there are too few '
            'verified appearances or eligible outcomes to rank them.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          for (final it in rec.insufficient) card(it, null),
        ],
        const SizedBox(height: 10),
        Text(
          'Match % reflects documented, comparable experience under methodology '
          '${rec.methodologyVersion}. It is not a prediction of success. Judge-specific '
          'experience never implies influence or a relationship.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted),
        ),
      ],
    );

    if (!wide) return results;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: Material(
            color: AppColors.surface,
            shape: const Border(right: BorderSide(color: AppColors.border)),
            child: FiltersPanel(recommendationId: _id),
          ),
        ),
        Expanded(child: results),
        SizedBox(
          width: 400,
          child: Material(
            color: AppColors.surface,
            shape: const Border(left: BorderSide(color: AppColors.border)),
            child: EvidencePanel(item: selected, recommendationId: _id),
          ),
        ),
      ],
    );
  }
}

class _ResultsHeader extends ConsumerWidget {
  const _ResultsHeader({
    required this.rec,
    required this.matter,
    required this.compareCount,
    required this.onCompare,
    required this.onFilters,
    required this.onMonitor,
  });

  final Recommendation rec;
  final Matter? matter;
  final int compareCount;
  final VoidCallback? onCompare;
  final VoidCallback? onFilters;
  final VoidCallback? onMonitor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final bench = rec.benchJudgeIds
        .map((id) => ref.watch(judgeNameProvider(id)))
        .join(' & ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recommended advocates', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(
            matter == null ? 'Recommendation ${rec.id}' : matter!.title,
            style: t.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(
                label:
                    '${rec.ranked.length} ranked · ${rec.insufficient.length} insufficient',
                color: AppColors.navy,
              ),
              Pill(
                label: bench.isEmpty ? 'No bench identified' : 'Bench: $bench',
                color: AppColors.teal,
                icon: Icons.gavel,
              ),
              Pill(
                label: rec.methodologyVersion,
                color: AppColors.neutral,
                icon: Icons.functions,
                tooltip: 'Scoring methodology version, for reproducibility',
              ),
              Pill(
                label: 'Run ${formatDate(rec.createdAt)}',
                color: AppColors.neutral,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SourcesSummary(runs: rec.sourceRuns),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onFilters != null)
                OutlinedButton.icon(
                  onPressed: onFilters,
                  icon: const Icon(Icons.tune),
                  label: const Text('Filters'),
                ),
              FilledButton.icon(
                onPressed: onCompare,
                icon: const Icon(Icons.compare_arrows),
                label: Text('Compare ($compareCount)'),
              ),
              OutlinedButton.icon(
                onPressed: onMonitor,
                icon: Icon(
                  matter?.monitored ?? false
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                ),
                label: Text(
                  matter?.monitored ?? false ? 'Monitoring' : 'Monitor changes',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showMethodology(context),
                icon: const Icon(Icons.help_outline),
                label: const Text('Methodology'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMethodology(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How the ranking works'),
        content: const SingleChildScrollView(
          child: Text(
            'S = 0.30·C + 0.20·F + 0.15·J + 0.20·O + 0.10·R + 0.05·V\n\n'
            'C  comparable case experience, weighted by relevance\n'
            'F  experience in the same court or forum\n'
            'J  experience before the identified bench (skipped and re-weighted if none)\n'
            'O  verified outcomes, smoothed toward 50% so small samples are not over-rewarded\n'
            'R  recency, with a three-year half-life\n'
            'V  share of appearances with a verified counsel role\n\n'
            'Only eligible, classifiable outcomes enter the favorable rate. Settled, '
            'withdrawn, procedural and indeterminate matters are excluded and listed.\n\n'
            'Advocates below the evidence threshold are shown as "insufficient '
            'evidence" rather than ranked.\n\n'
            'These are initial, configurable weights, not validated predictive '
            'probabilities. Every run records its methodology version.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SourcesSummary extends StatelessWidget {
  const _SourcesSummary({required this.runs});
  final List<SourceRun> runs;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningSoft,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          leading: const Icon(Icons.storage_outlined, color: AppColors.mixed),
          title: const Text(
            'Sources: live repositories not connected; demo index used',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final r in runs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: r.source == SourceType.userUpload
                    ? const IllustrativeTag(label: 'Demo index')
                    : SourceBadge(r.source),
                title: Text(r.status.label),
                subtitle: Text(r.message),
              ),
          ],
        ),
      ),
    );
  }
}
