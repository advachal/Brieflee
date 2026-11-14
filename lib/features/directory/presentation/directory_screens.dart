import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/case_type_subjects.dart';
import '../../../core/public_records/directory.dart';
import '../../../core/widgets/common.dart';
import '../../../shared/utilities/formatters.dart';
import '../../ask/application/ask_providers.dart';
import '../../ask/presentation/record_widgets.dart';
import '../../saved/application/saved_store.dart';
import 'live_search.dart';

Widget _withDirectory(
  WidgetRef ref,
  Widget Function(RecordsDirectory d) builder,
) {
  return ref
      .watch(directoryProvider)
      .when(
        loading: () => const LoadingView(
          label: 'Loading 109,341 Delhi High Court decisions…',
        ),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(publicRecordsProvider),
        ),
        data: builder,
      );
}

Widget _eyebrow(BuildContext context, String text) => Text(
  text.toUpperCase(),
  style: Theme.of(context).textTheme.labelMedium
      ?.copyWith(color: AppColors.gold, letterSpacing: 2),
);

/// Name filter that updates the list as the user types.
class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.hint,
    required this.onChanged,
    this.initial,
  });
  final String hint;
  final String? initial;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initial,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
    ),
  );
}

mixin _Debounced<T extends StatefulWidget> on State<T> {
  Timer? _t;
  String filter = '';

  void setFilter(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => filter = v.trim());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------

enum CounselSort { evidence, wins, appearances, recent }

/// Real advocates who appear in the records, ranked by decided outcomes.
class CounselDirectoryScreen extends ConsumerStatefulWidget {
  const CounselDirectoryScreen({super.key, this.subject, this.query});
  final String? subject;
  final String? query;

  @override
  ConsumerState<CounselDirectoryScreen> createState() =>
      _CounselDirectoryScreenState();
}

class _CounselDirectoryScreenState extends ConsumerState<CounselDirectoryScreen>
    with _Debounced {
  late String? _subject = widget.subject;
  CounselSort _sort = CounselSort.evidence;
  bool _includeGov = false;
  int _shown = 40;

  @override
  void initState() {
    super.initState();
    filter = widget.query ?? '';
  }

  @override
  void didUpdateWidget(covariant CounselDirectoryScreen old) {
    super.didUpdateWidget(old);
    if (widget.subject != old.subject) _subject = widget.subject;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _withDirectory(ref, (d) {
      List<CounselStat> list;
      if (filter.length >= 2) {
        list = d.searchCounsel(filter, subjectId: _subject);
      } else {
        list = [
          for (final c in d.counselFor(_subject))
            if (c.appearances > 0 && (_includeGov || !c.isGovernment)) c,
        ];
      }
      int byEvidence(CounselStat a, CounselStat b) {
        final ea = a.decided >= 3, eb = b.decided >= 3;
        if (ea != eb) return ea ? -1 : 1;
        final r = b.smoothedRate.compareTo(a.smoothedRate);
        return r != 0 ? r : b.appearances.compareTo(a.appearances);
      }

      if (filter.length < 2 || _sort != CounselSort.appearances) {
        list.sort(switch (_sort) {
          CounselSort.evidence => byEvidence,
          CounselSort.wins => (a, b) {
            final r = b.wins.compareTo(a.wins);
            return r != 0 ? r : a.losses.compareTo(b.losses);
          },
          CounselSort.appearances => (a, b) => b.appearances.compareTo(
            a.appearances,
          ),
          CounselSort.recent => (a, b) => (b.lastSeen ?? DateTime(0)).compareTo(
            a.lastSeen ?? DateTime(0),
          ),
        });
      }
      final subjectLabel = _subject == null
          ? null
          : subjectAreas.where((s) => s.id == _subject).firstOrNull?.label;

      return PageBody(
        maxWidth: 1100,
        children: [
          _eyebrow(context, 'Advocates · ${d.snapshot.courtNames}'),
          const SizedBox(height: 12),
          Text(
            subjectLabel == null ? 'Advocates' : 'Advocates in $subjectLabel',
            style: t.headlineLarge?.copyWith(color: AppColors.navy),
          ),
          const SizedBox(height: 8),
          Text(
            'Every advocate named in ${fmtInt(d.snapshot.records.length)} decisions, ${d.snapshot.yearRange}. '
            'Won and lost counts come only from judgments whose full text has been read and whose result is clear. '
            'Names are matched by spelling, so two advocates with the same name may be combined.',
            style: t.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          _FilterField(
            hint: 'Type a name, e.g. Sethi',
            initial: widget.query,
            onChanged: (v) {
              setFilter(v);
              _shown = 40;
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('All subjects'),
                selected: _subject == null,
                onSelected: (_) => setState(() {
                  _subject = null;
                  _shown = 40;
                }),
              ),
              for (final s in subjectAreas)
                if ((d.subjectCounts[s.id] ?? 0) > 0)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _subject == s.id,
                    onSelected: (_) => setState(() {
                      _subject = s.id;
                      _shown = 40;
                    }),
                  ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<CounselSort>(
                value: _sort,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: CounselSort.evidence,
                    child: Text('Sort: best decided record'),
                  ),
                  DropdownMenuItem(
                    value: CounselSort.wins,
                    child: Text('Sort: most wins'),
                  ),
                  DropdownMenuItem(
                    value: CounselSort.appearances,
                    child: Text('Sort: most appearances'),
                  ),
                  DropdownMenuItem(
                    value: CounselSort.recent,
                    child: Text('Sort: most recent'),
                  ),
                ],
                onChanged: (v) => setState(() => _sort = v!),
              ),
              FilterChip(
                label: const Text('Include government counsel'),
                selected: _includeGov,
                onSelected: (v) => setState(() => _includeGov = v),
              ),
              Text(
                '${fmtInt(list.length)} advocates',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'No advocate by that name',
              message: 'Try a surname only, or clear the subject filter.',
            )
          else
            for (var i = 0; i < list.length && i < _shown; i++)
              _CounselRow(rank: i + 1, stat: list[i]),
          if (list.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: OutlinedButton(
                  onPressed: () => setState(() => _shown += 60),
                  child: Text(
                    'Show more (${fmtInt(list.length - _shown)} left)',
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _CounselRow extends ConsumerWidget {
  const _CounselRow({required this.rank, required this.stat});
  final int rank;
  final CounselStat stat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final saved = ref.watch(savedProvider).counsel.containsKey(stat.id);
    final compact = MediaQuery.sizeOf(context).width < 640;
    final record = stat.decided == 0
        ? Text(
            'No decided outcome yet',
            style: t.bodySmall?.copyWith(color: AppColors.muted),
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${stat.wins} won',
                  style: const TextStyle(
                    color: AppColors.favorable,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: '  ·  '),
                TextSpan(
                  text: '${stat.losses} lost',
                  style: const TextStyle(
                    color: AppColors.unfavorable,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            style: t.bodyMedium,
          );
    return InkWell(
      onTap: () => context.go(Routes.recordCounsel(stat.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '$rank',
                style: t.titleMedium?.copyWith(color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.name,
                    style: t.titleMedium?.copyWith(color: AppColors.navy),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${fmtInt(stat.appearances)} appearances',
                      '${stat.petitionerSide} for petitioners, ${stat.respondentSide} for respondents',
                      if (stat.senior > 0) 'Senior Advocate in ${stat.senior}',
                      if (stat.isGovernment) 'mostly government counsel',
                    ].join(' · '),
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  if (compact) ...[const SizedBox(height: 4), record],
                ],
              ),
            ),
            if (!compact) SizedBox(width: 190, child: record),
            IconButton(
              tooltip: saved ? 'Remove from saved' : 'Save advocate',
              icon: Icon(
                saved ? Icons.bookmark : Icons.bookmark_border,
                color: saved ? AppColors.gold : AppColors.muted,
              ),
              onPressed: () => ref
                  .read(savedProvider.notifier)
                  .toggleCounsel(stat.id, stat.name),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

enum JudgeSort { decisions, recent, name }

class JudgesDirectoryScreen extends ConsumerStatefulWidget {
  const JudgesDirectoryScreen({super.key});

  @override
  ConsumerState<JudgesDirectoryScreen> createState() =>
      _JudgesDirectoryScreenState();
}

class _JudgesDirectoryScreenState extends ConsumerState<JudgesDirectoryScreen>
    with _Debounced {
  JudgeSort _sort = JudgeSort.decisions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _withDirectory(ref, (d) {
      final list = filter.length >= 2
          ? d.searchJudges(filter)
          : [
              for (final j in d.judges)
                if (j.decisions > 0) j,
            ];
      list.sort(switch (_sort) {
        JudgeSort.decisions => (a, b) => b.decisions.compareTo(a.decisions),
        JudgeSort.recent => (a, b) => (b.lastSeen ?? DateTime(0)).compareTo(
          a.lastSeen ?? DateTime(0),
        ),
        JudgeSort.name => (a, b) => a.name.compareTo(b.name),
      });
      return PageBody(
        children: [
          _eyebrow(context, 'Judges · ${d.snapshot.courtNames}'),
          const SizedBox(height: 12),
          Text(
            'Judges',
            style: t.headlineLarge?.copyWith(color: AppColors.navy),
          ),
          const SizedBox(height: 8),
          Text(
            'Judges named on the decisions, ${d.snapshot.yearRange}, as published by the court. '
            'Counts include orders as well as judgments; outcome splits use only judgments read in full.',
            style: t.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          _FilterField(hint: 'Type a judge\'s name', onChanged: setFilter),
          const SizedBox(height: 12),
          Row(
            children: [
              DropdownButton<JudgeSort>(
                value: _sort,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: JudgeSort.decisions,
                    child: Text('Sort: most decisions'),
                  ),
                  DropdownMenuItem(
                    value: JudgeSort.recent,
                    child: Text('Sort: most recent'),
                  ),
                  DropdownMenuItem(
                    value: JudgeSort.name,
                    child: Text('Sort: name'),
                  ),
                ],
                onChanged: (v) => setState(() => _sort = v!),
              ),
              const SizedBox(width: 16),
              Text(
                '${list.length} judges',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const EmptyState(
              icon: Icons.gavel_outlined,
              title: 'No judge by that name',
              message: 'Try the surname only.',
            ),
          for (final j in list)
            InkWell(
              onTap: () => context.go(Routes.recordJudge(j.id)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 4,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            j.name,
                            style: t.titleMedium?.copyWith(
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              '${fmtInt(j.decisions)} decisions',
                              '${fmtInt(j.judgments)} ${j.judgments == 1 ? 'judgment' : 'judgments'}',
                              if (j.petitionerOutcomes + j.respondentOutcomes >
                                  0)
                                'read in full: ${j.petitionerOutcomes} for petitioners, ${j.respondentOutcomes} for respondents',
                              if (j.lastSeen != null)
                                'latest ${formatDate(j.lastSeen!)}',
                            ].join(' · '),
                            style: t.bodySmall?.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------

/// The courts covered by the real records, with what is in each.
class CourtsOverviewScreen extends ConsumerWidget {
  const CourtsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return _withDirectory(ref, (d) {
      final s = d.snapshot;
      final k = s.knowledge;
      final decided =
          (k.outcomeCounts['petitioner'] ?? 0) +
          (k.outcomeCounts['respondent'] ?? 0);
      final activeCounsel = d.counsel.where((c) => c.appearances > 0).length;
      final activeJudges = d.judges.where((j) => j.decisions > 0).length;
      final subjects = [
        for (final a in subjectAreas)
          if ((d.subjectCounts[a.id] ?? 0) > 0) (a, d.subjectCounts[a.id]!),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      return PageBody(
        children: [
          _eyebrow(context, 'Courts'),
          const SizedBox(height: 12),
          Text(
            s.courtNames,
            style: t.headlineLarge?.copyWith(color: AppColors.navy),
          ),
          const SizedBox(height: 8),
          Text(
            'Decisions published by the court on the eCourts judgments portal, ${s.yearRange}, '
            'via the Indian High Court Judgments dataset on AWS Open Data (CC BY 4.0). '
            'More courts are added by running the same pipeline.',
            style: t.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              EvidenceNumber(
                value: fmtInt(s.records.length),
                label: 'decisions',
              ),
              EvidenceNumber(
                value: fmtInt(activeJudges),
                label: 'judges',
                onTap: () => context.go(Routes.judges()),
              ),
              EvidenceNumber(
                value: fmtInt(activeCounsel),
                label: 'advocates named',
                onTap: () => context.go(Routes.counsel()),
              ),
              EvidenceNumber(
                value: fmtInt(k.documents),
                label: 'judgments read in full',
              ),
              EvidenceNumber(
                value: fmtInt(decided),
                label: 'with a clear win or loss',
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionCard(
            title: 'Subjects',
            subtitle: 'By official case type. Open one to see the advocates with the best decided record in it.',
            child: Column(
              children: [
                for (final (a, n) in subjects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      a.label,
                      style: t.titleSmall?.copyWith(color: AppColors.navy),
                    ),
                    trailing: Text(
                      '${fmtInt(n)} decisions  ›',
                      style: t.bodyMedium?.copyWith(color: AppColors.teal),
                    ),
                    onTap: () => context.go(Routes.counsel(subject: a.id)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          RecordsAttribution(snapshot: s),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final saved = ref.watch(savedProvider);
    final store = ref.read(savedProvider.notifier);
    final dir = ref.watch(directoryProvider).value;
    return PageBody(
      children: [
        _eyebrow(context, 'Saved on this device'),
        const SizedBox(height: 12),
        Text('Saved', style: t.headlineLarge?.copyWith(color: AppColors.navy)),
        const SizedBox(height: 8),
        Text(
          'Advocates and searches you bookmark are kept in this browser only.',
          style: t.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Advocates',
          child: saved.counsel.isEmpty
              ? Text(
                  'None yet. Use the bookmark on an advocate to save them here.',
                  style: t.bodyMedium?.copyWith(color: AppColors.muted),
                )
              : Column(
                  children: [
                    for (final e in saved.counsel.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.person_outline,
                          color: AppColors.teal,
                        ),
                        title: Text(
                          e.value,
                          style: t.titleSmall?.copyWith(color: AppColors.navy),
                        ),
                        subtitle: dir == null || e.key >= dir.counsel.length
                            ? null
                            : Text(counselSummaryLine(dir.counsel[e.key])),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => store.toggleCounsel(e.key, e.value),
                        ),
                        onTap: () => context.go(Routes.recordCounsel(e.key)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Searches',
          child: saved.searches.isEmpty
              ? Text(
                  'None yet. Use “Save search” on an Ask result.',
                  style: t.bodyMedium?.copyWith(color: AppColors.muted),
                )
              : Column(
                  children: [
                    for (final q in saved.searches)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.search,
                          color: AppColors.teal,
                        ),
                        title: Text(
                          q,
                          style: t.titleSmall?.copyWith(color: AppColors.navy),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => store.toggleSearch(q),
                        ),
                        onTap: () => context.go(Routes.ask(q)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
