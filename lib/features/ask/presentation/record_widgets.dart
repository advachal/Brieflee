import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/knowledge.dart';
import '../../../core/public_records/public_records.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../shared/utilities/formatters.dart';

String recordDate(DateTime d) => formatDate(d);

String fmtInt(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

Future<void> openPdf(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $uri')));
  }
}

/// Outcome as a coloured pill. Non-eligible outcomes are neutral.
class RecordOutcomePill extends StatelessWidget {
  const RecordOutcomePill({super.key, required this.outcome, this.forSide});
  final RecordOutcome outcome;

  /// When set, shows the outcome from that side's point of view.
  final RecordSide? forSide;

  @override
  Widget build(BuildContext context) {
    if (forSide != null && outcome.eligible) {
      final won =
          (outcome == RecordOutcome.petitioner) ==
          (forSide == RecordSide.petitioner);
      return Pill(
        label: won
            ? 'Favourable for this counsel'
            : 'Unfavourable for this counsel',
        color: won ? AppColors.favorable : AppColors.unfavorable,
        icon: won ? Icons.check_circle_outline : Icons.cancel_outlined,
      );
    }
    final color = switch (outcome) {
      RecordOutcome.petitioner || RecordOutcome.respondent => AppColors.navy,
      RecordOutcome.unknown => AppColors.neutral,
      _ => AppColors.mixed,
    };
    return Pill(label: outcome.label, color: color);
  }
}

/// One real decision in a list.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.snapshot,
    required this.record,
    this.matched = const [],
    this.forCounsel,
    this.dense = false,
  });

  final PublicRecordsSnapshot snapshot;
  final CourtRecord record;
  final List<String> matched;

  /// When set, the outcome is shown from this counsel's side.
  final int? forCounsel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = snapshot.knowledgeFor(record);
    final outcome = snapshot.outcomeOf(record);
    RecordSide? side;
    if (forCounsel != null) {
      for (final c in snapshot.counselFor(record)) {
        if (c.counselId == forCounsel) side = c.side;
      }
    }
    return InkWell(
      onTap: () => context.go(Routes.record(record.id)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 12 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  snapshot.caseNumber(record),
                  style: t.labelLarge?.copyWith(
                    color: AppColors.teal,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  '·  ${recordDate(record.date)}',
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
                if (k != null)
                  RecordOutcomePill(outcome: outcome, forSide: side),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              record.title,
              style: (dense ? t.titleMedium : t.titleLarge)?.copyWith(
                color: AppColors.navy,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (record.judgeIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                record.judgeIds.map((j) => snapshot.judges[j]).join(', '),
                style: t.bodySmall?.copyWith(color: AppColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (k != null && k.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.gold, width: 2),
                  ),
                ),
                child: Text(
                  '“${k.evidence}”',
                  style: t.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.ink,
                  ),
                  maxLines: dense ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (matched.isNotEmpty && !dense) ...[
              const SizedBox(height: 8),
              Text(
                'Matched: ${matched.toSet().take(8).join(', ')}',
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows the exact decisions behind a number.
Future<void> showRecordsSheet(
  BuildContext context, {
  required PublicRecordsSnapshot snapshot,
  required String title,
  required List<int> recordIndexes,
  String? note,
  int? forCounsel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text(
            title,
            style: Theme.of(ctx).textTheme.headlineSmall
                ?.copyWith(color: AppColors.navy),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: Theme.of(ctx).textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 8),
          for (final i in recordIndexes) ...[
            const Divider(height: 1),
            RecordTile(
              snapshot: snapshot,
              record: snapshot.records[i],
              forCounsel: forCounsel,
              dense: true,
            ),
          ],
          if (recordIndexes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No decisions.'),
            ),
        ],
      ),
    ),
  );
}

/// A tappable number with its label, in the editorial style.
class EvidenceNumber extends StatelessWidget {
  const EvidenceNumber({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
    this.color = AppColors.navy,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: t.headlineSmall?.copyWith(color: color, height: 1.1),
          ),
          Text(
            label,
            style: t.bodySmall?.copyWith(
              color: AppColors.muted,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: AppColors.border,
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? child
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: child,
          );
  }
}

/// Source and licence, shown wherever real records appear.
class RecordsAttribution extends StatelessWidget {
  const RecordsAttribution({super.key, required this.snapshot});
  final PublicRecordsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Text(
        '${snapshot.meta.attribution} Snapshot built ${formatDate(DateTime.parse(snapshot.meta.built))}. '
        'Outcomes are read from the operative sentence of each order by rules, not by AI, and are shown with that '
        'sentence. Settled, withdrawn, interim and unclear orders are never counted as wins or losses. Counsel names '
        'are matched by spelling, so two advocates with the same name can be merged.',
        style: t.bodySmall?.copyWith(color: AppColors.muted, height: 1.5),
      ),
    );
  }
}
