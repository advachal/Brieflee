import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/case_type_subjects.dart';
import '../../../core/public_records/knowledge.dart';
import '../../../core/public_records/public_records.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../application/ask_providers.dart';
import 'record_widgets.dart';
import '../../saved/application/saved_store.dart';

Widget _withSnapshot(
  WidgetRef ref,
  Widget Function(PublicRecordsSnapshot s) builder,
) {
  final snap = ref.watch(publicRecordsProvider);
  return snap.when(
    loading: () => const LoadingView(label: 'Loading High Court records…'),
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

/// Case-type subject breakdown for a list of records.
List<MapEntry<String, List<int>>> _bySubject(
  PublicRecordsSnapshot s,
  List<CourtRecord> records,
) {
  final m = <String, List<int>>{};
  for (final r in records) {
    final t = s.caseTypes[r.caseTypeId];
    final subject =
        subjectAreas
            .where((a) => a.matches(t))
            .map((a) => a.label)
            .firstOrNull ??
        'Other ($t)';
    (m[subject] ??= []).add(r.index);
  }
  return m.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
}

// ---------------------------------------------------------------------------

class RecordCaseScreen extends ConsumerWidget {
  const RecordCaseScreen({super.key, required this.recordId});
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _withSnapshot(ref, (s) {
      final r = s.byId(recordId);
      if (r == null) {
        return const EmptyState(
          icon: Icons.search_off,
          title: 'Decision not found',
          message: 'It is not in the bundled High Court snapshot.',
        );
      }
      final t = Theme.of(context).textTheme;
      final k = s.knowledgeFor(r);
      final outcome = s.outcomeOf(r);
      final counsel = s.counselFor(r);
      Widget side(RecordSide side) {
        final list = counsel.where((c) => c.side == side).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              side.label,
              style: t.titleMedium?.copyWith(color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            if (list.isEmpty)
              Text('Not named in the header we read.', style: t.bodySmall),
            for (final c in list)
              InkWell(
                onTap: () => context.go(Routes.recordCounsel(c.counselId)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.counselName(c.counselId),
                          style: t.bodyLarge?.copyWith(
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.border,
                          ),
                        ),
                      ),
                      if (c.role != CounselRole.advocate) ...[
                        const SizedBox(width: 8),
                        Pill(label: c.role.label, color: AppColors.muted),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      }

      return PageBody(
        children: [
          _eyebrow(context, '${s.courtOf(r).court} · ${s.caseNumber(r)}'),
          const SizedBox(height: 12),
          Text(
            r.title,
            style: t.headlineLarge?.copyWith(color: AppColors.navy),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                recordDate(r.date),
                style: t.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              Pill(label: r.docType.label, color: AppColors.muted),
              if (k != null) RecordOutcomePill(outcome: outcome),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => openPdf(context, s.pdfUri(r)),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Open the official judgment (PDF)'),
              ),
              OutlinedButton(
                onPressed: () => context.go(
                  Routes.ask(
                    '${s.caseType(r)} ${r.petitioner} ${r.respondent}',
                  ),
                ),
                child: const Text('Ask about similar matters'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionCard(
            title: 'Outcome',
            child: k == null
                ? Text(
                    'This order has not been read in full yet (only commercial, arbitration and IP judgments are in the '
                    'knowledge layer), so its outcome is not recorded. Open the PDF to read it.',
                    style: t.bodyMedium,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        outcome.label,
                        style: t.titleLarge?.copyWith(color: AppColors.navy),
                      ),
                      if (k.evidence.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Read from this sentence of the order:',
                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          '“${k.evidence}”',
                          style: t.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        outcome.eligible
                            ? 'Counted toward counsel favourable rates.'
                            : 'Not counted toward any favourable rate.',
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Bench',
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final j in r.judgeIds)
                  ActionChip(
                    label: Text(s.judges[j]),
                    onPressed: () => context.go(Routes.recordJudge(j)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Counsel',
            subtitle: k != null ? 'From the full judgment header.' : 'From the first lines of the judgment only, so this list may be incomplete.',
            child: LayoutBuilder(
              builder: (context, c) => c.maxWidth > 640
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: side(RecordSide.petitioner)),
                        const SizedBox(width: 24),
                        Expanded(child: side(RecordSide.respondent)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        side(RecordSide.petitioner),
                        const SizedBox(height: 16),
                        side(RecordSide.respondent),
                      ],
                    ),
            ),
          ),
          if (k != null && (k.statutes.isNotEmpty || k.terms.isNotEmpty)) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Statutes and key terms',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final st in k.statutes)
                    Pill(label: st, color: AppColors.navy),
                  for (final w in k.terms.take(18))
                    Pill(label: w, color: AppColors.muted),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SectionCard(
            title: 'Record',
            child: Column(
              children: [
                KeyValueRow('CNR', r.cnr),
                KeyValueRow('Case type', s.caseType(r)),
                KeyValueRow('Registered', '${r.regYear}'),
                KeyValueRow('Decision date', recordDate(r.date)),
                if (k != null) KeyValueRow('Pages', '${k.pages}'),
                KeyValueRow('Source PDF', s.pdfUri(r).toString()),
              ],
            ),
          ),
          RecordsAttribution(snapshot: s),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------

class RecordCounselScreen extends ConsumerWidget {
  const RecordCounselScreen({super.key, required this.counselId});
  final int counselId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _withSnapshot(ref, (s) {
      final t = Theme.of(context).textTheme;
      final name = s.counselName(counselId);
      final records = s.recordsForCounsel(counselId);
      final fav = <int>[], unfav = <int>[], other = <int>[], read = <int>[];
      var pSide = 0, rSide = 0, senior = 0;
      final judges = <int, List<int>>{};
      for (final r in records) {
        final a = s.counselFor(r).firstWhere((c) => c.counselId == counselId);
        if (a.side == RecordSide.petitioner) {
          pSide++;
        } else {
          rSide++;
        }
        if (a.role == CounselRole.senior) senior++;
        for (final j in r.judgeIds) {
          (judges[j] ??= []).add(r.index);
        }
        if (s.knowledgeFor(r) == null) continue;
        read.add(r.index);
        final o = s.outcomeOf(r);
        if (o.eligible) {
          final won =
              (o == RecordOutcome.petitioner) ==
              (a.side == RecordSide.petitioner);
          (won ? fav : unfav).add(r.index);
        } else {
          other.add(r.index);
        }
      }
      final topJudges = judges.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      final subjects = _bySubject(s, records);

      return PageBody(
        children: [
          _eyebrow(
            context,
            'Counsel · ${records.isEmpty ? s.courtNames : s.courtOf(records.first).court}',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: t.headlineLarge?.copyWith(color: AppColors.navy),
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final saved = ref
                      .watch(savedProvider)
                      .counsel
                      .containsKey(counselId);
                  return OutlinedButton.icon(
                    onPressed: () => ref
                        .read(savedProvider.notifier)
                        .toggleCounsel(counselId, name),
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      size: 18,
                    ),
                    label: Text(saved ? 'Saved' : 'Save'),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Everything below is drawn from decisions in which this name appears as counsel, ${s.yearRange}. '
            'Names are matched by spelling, so different advocates with the same name may be combined. '
            'Appearance counts are not a measure of quality.',
            style: t.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              EvidenceNumber(
                value: fmtInt(records.length),
                label: 'appearances',
                onTap: () => showRecordsSheet(
                  context,
                  snapshot: s,
                  title: '$name: all appearances',
                  recordIndexes: [for (final r in records) r.index],
                  forCounsel: counselId,
                ),
              ),
              EvidenceNumber(
                value: '$pSide / $rSide',
                label: 'petitioner / respondent side',
              ),
              if (senior > 0)
                EvidenceNumber(value: '$senior', label: 'as Senior Advocate'),
              EvidenceNumber(
                value: '${fav.length}',
                label: 'favourable decided outcomes',
                color: AppColors.favorable,
                onTap: () => showRecordsSheet(
                  context,
                  snapshot: s,
                  title: '$name: favourable outcomes',
                  recordIndexes: fav,
                  forCounsel: counselId,
                ),
              ),
              EvidenceNumber(
                value: '${unfav.length}',
                label: 'unfavourable decided outcomes',
                color: AppColors.unfavorable,
                onTap: () => showRecordsSheet(
                  context,
                  snapshot: s,
                  title: '$name: unfavourable outcomes',
                  recordIndexes: unfav,
                  forCounsel: counselId,
                ),
              ),
              EvidenceNumber(
                value: '${other.length}',
                label: 'settled, withdrawn, interim or unclear',
                onTap: () => showRecordsSheet(
                  context,
                  snapshot: s,
                  title: '$name: not counted',
                  recordIndexes: other,
                  forCounsel: counselId,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Outcomes are known only for the ${read.length} of these decisions whose full text has been read '
            '(commercial, arbitration and IP).',
            style: t.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          SectionCard(
            title: 'Subjects',
            child: Column(
              children: [
                for (final e in subjects.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.key),
                    trailing: Text('${e.value.length}'),
                    onTap: () => showRecordsSheet(
                      context,
                      snapshot: s,
                      title: '$name: ${e.key}',
                      recordIndexes: e.value,
                      forCounsel: counselId,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Benches appeared before',
            child: Column(
              children: [
                for (final e in topJudges.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.judges[e.key]),
                    trailing: Text('${e.value.length}'),
                    onTap: () => showRecordsSheet(
                      context,
                      snapshot: s,
                      title: '$name before ${s.judges[e.key]}',
                      recordIndexes: e.value,
                      forCounsel: counselId,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Recent decisions',
            style: t.headlineSmall?.copyWith(color: AppColors.navy),
          ),
          for (final r in records.take(20)) ...[
            const Divider(height: 1),
            RecordTile(
              snapshot: s,
              record: r,
              forCounsel: counselId,
              dense: true,
            ),
          ],
          RecordsAttribution(snapshot: s),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------

class RecordJudgeScreen extends ConsumerWidget {
  const RecordJudgeScreen({super.key, required this.judgeId});
  final int judgeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _withSnapshot(ref, (s) {
      final t = Theme.of(context).textTheme;
      final name = s.judges[judgeId];
      final records = s.recordsForJudge(judgeId);
      final subjects = _bySubject(s, records);
      final counsel = <int, List<int>>{};
      var p = 0, rr = 0;
      for (final r in records) {
        final o = s.outcomeOf(r);
        if (o == RecordOutcome.petitioner) p++;
        if (o == RecordOutcome.respondent) rr++;
        for (final c in s.counselFor(r)) {
          if (c.role == CounselRole.government) continue;
          final l = counsel[c.counselId] ??= [];
          if (l.isEmpty || l.last != r.index) l.add(r.index);
        }
      }
      final topCounsel = counsel.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      return PageBody(
        children: [
          _eyebrow(
            context,
            'Bench · ${records.isEmpty ? s.courtNames : s.courtOf(records.first).court}',
          ),
          const SizedBox(height: 12),
          Text(name, style: t.headlineLarge?.copyWith(color: AppColors.navy)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              EvidenceNumber(
                value: fmtInt(records.length),
                label: 'decisions, ${s.yearRange}',
              ),
              EvidenceNumber(
                value: '$p',
                label: 'petitioner side succeeded (read in full)',
              ),
              EvidenceNumber(
                value: '$rr',
                label: 'respondent side succeeded (read in full)',
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionCard(
            title: 'Subjects',
            child: Column(
              children: [
                for (final e in subjects.take(10))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.key),
                    trailing: Text('${e.value.length}'),
                    onTap: () => showRecordsSheet(
                      context,
                      snapshot: s,
                      title: '$name: ${e.key}',
                      recordIndexes: e.value,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Counsel who appeared most often',
            subtitle: 'Private counsel only. Appearance counts are not a measure of quality.',
            child: Column(
              children: [
                for (final e in topCounsel.take(10))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.counselName(e.key)),
                    trailing: Text('${e.value.length}'),
                    onTap: () => context.go(Routes.recordCounsel(e.key)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Recent decisions',
            style: t.headlineSmall?.copyWith(color: AppColors.navy),
          ),
          for (final r in records.take(20)) ...[
            const Divider(height: 1),
            RecordTile(snapshot: s, record: r, dense: true),
          ],
          RecordsAttribution(snapshot: s),
        ],
      );
    });
  }
}
