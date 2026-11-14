import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/ask_engine.dart';
import '../../../core/public_records/public_records.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../application/ask_providers.dart';
import '../data/document_text.dart';
import 'record_widgets.dart';

const _examples = [
  'Challenging an arbitral award under section 34 for patent illegality',
  'Trademark infringement suit for a pharmaceutical brand, we are the plaintiff',
  'Appointment of arbitrator under section 11 in a construction contract',
  'Defending a commercial recovery suit on unpaid invoices',
  'Extension of arbitral mandate under section 29A',
  'Patent infringement interim injunction',
];

/// Ask: type a question in plain English, get similar real decisions and the
/// counsel who won them, all computed live from the knowledge layer.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  late String _query = widget.initialQuery?.trim() ?? '';
  SideChoice _side = SideChoice.auto;

  /// An uploaded document, read on this device.
  ({String name, String text})? _doc;
  bool _reading = false;
  String? _docError;

  @override
  void didUpdateWidget(covariant AskScreen old) {
    super.didUpdateWidget(old);
    final q = widget.initialQuery?.trim() ?? '';
    if (q != _query) {
      _c.text = q;
      setState(() => _query = q);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit([String? text]) {
    final q = (text ?? _c.text).trim();
    if (text != null) _c.text = text;
    setState(() {
      _query = q;
      _doc = null;
    });
    context.go(Routes.ask(q.isEmpty ? null : q));
  }

  Future<void> _upload() async {
    setState(() {
      _docError = null;
    });
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: uploadExtensions,
    );
    final file = picked.singleOrNull;
    if (file == null) return;
    setState(() => _reading = true);
    try {
      final text = await extractDocumentText(
        file.name,
        await file.readAsBytes(),
      );
      if (text.trim().length < 200) {
        setState(() {
          _docError =
              'Could not read enough text from ${file.name}. If it is a scanned PDF, paste the key paragraphs instead.';
          _reading = false;
        });
        return;
      }
      setState(() {
        _doc = (name: file.name, text: text);
        _reading = false;
      });
    } catch (e) {
      setState(() {
        _docError = '$e';
        _reading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final engine = ref.watch(askEngineProvider);

    return PageBody(
      maxWidth: 1180,
      children: [
        Text(
          'ASK THE RECORDS',
          style: t.labelMedium?.copyWith(
            color: AppColors.gold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Who has won matters like mine?',
          style: (compact ? t.headlineMedium : t.displaySmall)?.copyWith(
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Describe the dispute in your own words. The answer is built while you wait from real High Court '
          'decisions: similar matters, how they ended, and the counsel on the winning side.',
          style: t.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        _QueryBox(controller: _c, onSubmit: _submit),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _reading ? null : _upload,
              icon: _reading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file, size: 18),
              label: Text(
                _reading ? 'Reading…' : 'Upload a judgment or pleading (PDF)',
              ),
            ),
            SegmentedButton<SideChoice>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SideChoice.auto, label: Text('Any side')),
                ButtonSegment(
                  value: SideChoice.petitioner,
                  label: Text('Petitioner'),
                ),
                ButtonSegment(
                  value: SideChoice.respondent,
                  label: Text('Respondent'),
                ),
              ],
              selected: {_side},
              onSelectionChanged: (v) => setState(() => _side = v.first),
            ),
          ],
        ),
        if (_docError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _docError!,
              style: t.bodyMedium?.copyWith(color: AppColors.unfavorable),
            ),
          ),
        const SizedBox(height: 14),
        if (_query.isEmpty && _doc == null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _examples)
                ActionChip(label: Text(e), onPressed: () => _submit(e)),
            ],
          ),
        const SizedBox(height: 12),
        engine.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: LoadingView(
              label: 'Loading 109,341 Delhi High Court decisions and the knowledge layer…',
            ),
          ),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(publicRecordsProvider),
          ),
          data: (engine) {
            if (_doc != null) {
              final q = engine.documentQuery(_doc!.text);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DocBanner(
                    name: _doc!.name,
                    chars: _doc!.text.length,
                    onClear: () => setState(() => _doc = null),
                  ),
                  const SizedBox(height: 16),
                  _Results(
                    engine: engine,
                    query: q,
                    side: _side,
                    fromDocument: true,
                  ),
                ],
              );
            }
            return _query.isEmpty
                ? _Coverage(snapshot: engine.snapshot)
                : _Results(engine: engine, query: _query, side: _side);
          },
        ),
      ],
    );
  }
}

class _QueryBox extends StatelessWidget {
  const _QueryBox({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final void Function([String?]) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'e.g. Our client wants to set aside an arbitral award under section 34…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => onSubmit(),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Ask'),
          ),
        ],
      ),
    );
  }
}

class _Coverage extends StatelessWidget {
  const _Coverage({required this.snapshot});
  final PublicRecordsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = snapshot.knowledge;
    final eligible =
        (k.outcomeCounts['petitioner'] ?? 0) +
        (k.outcomeCounts['respondent'] ?? 0);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 20),
          Text(
            'What the answers draw on',
            style: t.headlineSmall?.copyWith(color: AppColors.navy),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              EvidenceNumber(
                value: fmtInt(snapshot.records.length),
                label: 'decisions, ${snapshot.yearRange}',
              ),
              EvidenceNumber(
                value: fmtInt(k.documents),
                label: 'judgments read in full (commercial, arbitration, IP)',
              ),
              EvidenceNumber(
                value: fmtInt(eligible),
                label: 'with a clear win or loss',
              ),
              EvidenceNumber(
                value: fmtInt(snapshot.judges.length),
                label: 'judges',
              ),
              EvidenceNumber(
                value: fmtInt(snapshot.counselCount),
                label: 'counsel names',
              ),
            ],
          ),
          RecordsAttribution(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _DocBanner extends StatelessWidget {
  const _DocBanner({
    required this.name,
    required this.chars,
    required this.onClear,
  });
  final String name;
  final int chars;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: t.titleMedium?.copyWith(color: AppColors.navy),
                ),
                Text(
                  'Read on this device (${fmtInt(chars)} characters, not uploaded anywhere). Matched on its '
                  'statutes and most distinctive terms; names of parties, judges and counsel in it are not used.',
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove document',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.engine,
    required this.query,
    this.side = SideChoice.auto,
    this.fromDocument = false,
  });
  final AskEngine engine;
  final String query;
  final SideChoice side;
  final bool fromDocument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer = engine.ask(query, side: side);
    final snapshot = engine.snapshot;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final generated = ref.watch(generatedAnswerProvider(query));

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnswerCard(answer: answer, generated: generated.value),
        const SizedBox(height: 28),
        _CounselSection(answer: answer, snapshot: snapshot),
        const SizedBox(height: 28),
        _JudgesSection(answer: answer, snapshot: snapshot),
      ],
    );
    final right = _DecisionsSection(answer: answer, snapshot: snapshot);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Interpretation(answer: answer, snapshot: snapshot),
        const SizedBox(height: 20),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: left),
              const SizedBox(width: 40),
              Expanded(flex: 6, child: right),
            ],
          )
        else ...[
          left,
          const SizedBox(height: 28),
          right,
        ],
        RecordsAttribution(snapshot: snapshot),
      ],
    );
  }
}

class _Interpretation extends StatelessWidget {
  const _Interpretation({required this.answer, required this.snapshot});
  final AskAnswer answer;
  final PublicRecordsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final it = answer.interpretation;
    final t = Theme.of(context).textTheme;
    final chips = <Widget>[
      for (final s in it.subjects)
        Pill(
          label: s.label,
          color: AppColors.navy,
          icon: Icons.category_outlined,
        ),
      for (final s in it.sections)
        Pill(
          label: 'Section $s',
          color: AppColors.navy,
          icon: Icons.menu_book_outlined,
        ),
      for (final j in it.judgeIds)
        Pill(
          label: snapshot.judges[j],
          color: AppColors.teal,
          icon: Icons.gavel,
        ),
      for (final c in it.counselIds)
        Pill(
          label: snapshot.counselName(c),
          color: AppColors.teal,
          icon: Icons.person_outline,
        ),
      for (final y in it.years) Pill(label: '$y', color: AppColors.muted),
      if (it.caseNumber != null)
        Pill(
          label: 'No. ${it.caseNumber!.no}/${it.caseNumber!.year}',
          color: AppColors.muted,
        ),
      if (it.side != null)
        Pill(
          label: 'You: ${it.side!.label.toLowerCase()}',
          color: AppColors.gold,
        ),
      for (final w in it.terms.take(10)) Pill(label: w, color: AppColors.muted),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How we read your question',
          style: t.labelLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, this.generated});
  final AskAnswer answer;
  final String? generated;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ANSWER',
            style: t.labelMedium?.copyWith(
              color: AppColors.gold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            answer.summary,
            style: t.titleMedium?.copyWith(
              color: Colors.white,
              fontSize: 19,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (generated != null) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'GROUNDED SUMMARY · AI, CITES THE DECISIONS',
              style: t.labelSmall?.copyWith(
                color: AppColors.gold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              generated!,
              style: t.bodyLarge?.copyWith(color: Colors.white, height: 1.5),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            generated == null
                ? 'Built from the records by fixed rules. No text is generated by AI.'
                : 'The first paragraph is computed by rules; the summary was generated from the retrieved passages only.',
            style: t.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _CounselSection extends StatelessWidget {
  const _CounselSection({required this.answer, required this.snapshot});
  final AskAnswer answer;
  final PublicRecordsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Counsel who won similar matters',
          style: t.headlineSmall?.copyWith(color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(
          'Ranked on decided outcomes in the similar decisions (favourable rate smoothed toward 50%), how many similar '
          'matters they handled, and whether they acted for your side. At least ${AskEngine.minEligible} decided '
          'outcomes, at least one win and a favourable rate of 50% or more are needed to be listed here. Government panel counsel are left out. This is evidence, not an '
          'endorsement or a prediction.',
          style: t.bodySmall?.copyWith(color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 10),
        if (answer.counsel.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Not enough decided outcomes among these similar matters to rank anyone yet.',
              style: t.bodyLarge,
            ),
          ),
        for (var i = 0; i < answer.counsel.length; i++) ...[
          const Divider(height: 1),
          _CounselRow(rank: i + 1, e: answer.counsel[i], snapshot: snapshot),
        ],
        if (answer.insufficient.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Also appeared (not enough decided outcomes, or no favourable record)',
            style: t.titleSmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in answer.insufficient)
                ActionChip(
                  label: Text('${e.name} · ${e.similar.length}'),
                  onPressed: () => showRecordsSheet(
                    context,
                    snapshot: snapshot,
                    title: '${e.name}: similar matters',
                    recordIndexes: e.similar,
                    forCounsel: e.counselId,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CounselRow extends StatelessWidget {
  const _CounselRow({
    required this.rank,
    required this.e,
    required this.snapshot,
  });
  final int rank;
  final CounselEvidence e;
  final PublicRecordsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$rank',
              style: t.headlineSmall?.copyWith(color: AppColors.gold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.go(Routes.recordCounsel(e.counselId)),
                  child: Text(
                    e.name,
                    style: t.titleLarge?.copyWith(
                      color: AppColors.navy,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.border,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Acted for petitioners ${e.petitionerSide}×, respondents ${e.respondentSide}× in these matters',
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 28,
                  runSpacing: 8,
                  children: [
                    EvidenceNumber(
                      value: '${e.favourable.length}',
                      label: 'favourable',
                      color: AppColors.favorable,
                      onTap: () => showRecordsSheet(
                        context,
                        snapshot: snapshot,
                        title: '${e.name}: favourable outcomes',
                        recordIndexes: e.favourable,
                        forCounsel: e.counselId,
                      ),
                    ),
                    EvidenceNumber(
                      value: '${e.unfavourable.length}',
                      label: 'unfavourable',
                      color: AppColors.unfavorable,
                      onTap: () => showRecordsSheet(
                        context,
                        snapshot: snapshot,
                        title: '${e.name}: unfavourable outcomes',
                        recordIndexes: e.unfavourable,
                        forCounsel: e.counselId,
                      ),
                    ),
                    EvidenceNumber(
                      value: '${e.similar.length}',
                      label: 'similar matters',
                      onTap: () => showRecordsSheet(
                        context,
                        snapshot: snapshot,
                        title: '${e.name}: similar matters',
                        note: 'Includes settled, withdrawn and interim orders, which are not counted as outcomes.',
                        recordIndexes: e.similar,
                        forCounsel: e.counselId,
                      ),
                    ),
                    EvidenceNumber(
                      value: '${(e.smoothedRate * 100).round()}%',
                      label: 'smoothed favourable rate',
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              e.score.round().toString(),
              textAlign: TextAlign.right,
              style: t.headlineMedium?.copyWith(color: AppColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}

class _JudgesSection extends StatelessWidget {
  const _JudgesSection({required this.answer, required this.snapshot});
  final AskAnswer answer;
  final PublicRecordsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (answer.judges.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Benches that decided them',
          style: t.headlineSmall?.copyWith(color: AppColors.navy),
        ),
        const SizedBox(height: 8),
        for (final j in answer.judges) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(j.name),
            onTap: () => context.go(Routes.recordJudge(j.judgeId)),
            trailing: TextButton(
              onPressed: () => showRecordsSheet(
                context,
                snapshot: snapshot,
                title: '${j.name}: similar decisions',
                recordIndexes: j.recordIndexes,
              ),
              child: Text('${j.recordIndexes.length} decisions'),
            ),
          ),
        ],
      ],
    );
  }
}

class _DecisionsSection extends StatefulWidget {
  const _DecisionsSection({required this.answer, required this.snapshot});
  final AskAnswer answer;
  final PublicRecordsSnapshot snapshot;

  @override
  State<_DecisionsSection> createState() => _DecisionsSectionState();
}

class _DecisionsSectionState extends State<_DecisionsSection> {
  int _shown = 15;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hits = widget.answer.hits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Similar decisions',
          style: t.headlineSmall?.copyWith(color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(
          'Most similar first. Each opens the case, its counsel and the official judgment PDF.',
          style: t.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        if (hits.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'No similar decisions',
            message: 'Try naming the subject, a statute section, a party, or a judge.',
          ),
        for (final h in hits.take(_shown)) ...[
          const Divider(height: 1),
          RecordTile(
            snapshot: widget.snapshot,
            record: h.record,
            matched: h.matchedTerms,
          ),
        ],
        if (hits.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: () => setState(() => _shown += 20),
              child: Text('Show more (${hits.length - _shown} left)'),
            ),
          ),
      ],
    );
  }
}
