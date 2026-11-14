import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/ask_engine.dart';
import '../../../core/public_records/case_type_subjects.dart';
import '../../../core/public_records/matter_facts.dart';
import '../../../core/public_records/public_records.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../application/ask_providers.dart';
import '../data/document_text.dart';
import 'matter_facts_panel.dart';
import 'record_widgets.dart';
import '../../saved/application/saved_store.dart';

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
  const AskScreen({super.key, this.initialQuery, this.openUpload = false});
  final String? initialQuery;

  /// Opened from "Upload a judgment": lead with the upload action.
  final bool openUpload;

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  late String _query = widget.initialQuery?.trim() ?? '';
  SideChoice _side = SideChoice.auto;

  /// Optional filters for typed questions.
  String? _subjectFilter;
  int? _benchFilter;

  /// An uploaded document, read on this device.
  ({String name, String text})? _doc;
  bool _reading = false;
  String? _docError;

  /// Facts read from the document (on the device, then merged with the AI
  /// reading when it arrives), and the facts the user confirmed.
  MatterFacts? _facts;
  bool _aiMerged = false;
  MatterFacts? _confirmed;

  void _clearDoc() {
    _doc = null;
    _facts = null;
    _aiMerged = false;
    _confirmed = null;
  }

  @override
  void didUpdateWidget(covariant AskScreen old) {
    super.didUpdateWidget(old);
    final q = widget.initialQuery?.trim() ?? '';
    if (q != _query) {
      _c.text = q;
      setState(() => _query = q);
    }
  }

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Real-time search: results follow the text as it is typed.
  void _typed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (!mounted || q == _query) return;
      if (q.isEmpty || q.length >= 3) {
        setState(() {
          _query = q;
          _clearDoc();
        });
      }
    });
  }

  void _submit([String? text]) {
    final q = (text ?? _c.text).trim();
    if (text != null) _c.text = text;
    setState(() {
      _query = q;
      _clearDoc();
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
        _clearDoc();
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
        if (widget.openUpload && _doc == null && _query.isEmpty) ...[
          _UploadLead(reading: _reading, onUpload: _upload),
          const SizedBox(height: 20),
        ],
        _QueryBox(controller: _c, onSubmit: _submit, onChanged: _typed),
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
        if (_doc == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _Filters(
              snapshot: engine.value?.snapshot,
              subjectId: _subjectFilter,
              benchJudgeId: _benchFilter,
              onSubject: (v) => setState(() => _subjectFilter = v),
              onBench: (v) => setState(() => _benchFilter = v),
            ),
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
            if (_doc != null) return _documentFlow(engine);
            if (_query.isEmpty) return _Coverage(snapshot: engine.snapshot);
            final saved = ref.watch(savedProvider).searches.contains(_query);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        ref.read(savedProvider.notifier).toggleSearch(_query),
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      size: 18,
                    ),
                    label: Text(saved ? 'Saved' : 'Save search'),
                  ),
                ),
                _Results(
                  engine: engine,
                  query: _query,
                  side: _side,
                  subjectId: _subjectFilter,
                  benchJudgeId: _benchFilter,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Upload → check the facts → recommend.
  Widget _documentFlow(AskEngine engine) {
    final text = _doc!.text;
    final service = ref.watch(knowledgeServiceProvider).configured;
    _facts ??= FactExtractor(engine.snapshot).extract(text);
    String? status;
    if (service) {
      final ai = ref.watch(documentFactsProvider(text));
      if (ai.isLoading) {
        status = 'The AI is reading the whole document; the fields below may fill in further when it finishes.';
      } else if (ai.value != null) {
        if (!_aiMerged) {
          final merged = _facts!.copy();
          mergeAiFacts(merged, ai.value!, engine.snapshot);
          _facts = merged;
          _aiMerged = true;
        }
      } else {
        status = 'The AI reading is not available right now; these facts were read on this device.';
      }
    }
    final banner = _DocBanner(
      name: _doc!.name,
      chars: text.length,
      service: service,
      onClear: () => setState(_clearDoc),
    );
    final confirmed = _confirmed;
    if (confirmed == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          banner,
          const SizedBox(height: 16),
          MatterFactsPanel(
            facts: _facts!,
            snapshot: engine.snapshot,
            aiStatus: status,
            onConfirm: (f) => setState(() => _confirmed = f),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        const SizedBox(height: 16),
        _ConfirmedFacts(
          facts: confirmed,
          snapshot: engine.snapshot,
          onEdit: () => setState(() {
            _facts = confirmed;
            _confirmed = null;
          }),
        ),
        const SizedBox(height: 16),
        _ServiceAnalysis(
          request: jsonEncode({
            'text': text,
            if (confirmed.side != null)
              'side': confirmed.side == RecordSide.petitioner ? 'p' : 'r',
            'facts': {
              'issues': confirmed.issues,
              'statutes': confirmed.statutes,
              'summary': confirmed.summary,
              'subject': confirmed.subject?.label,
            },
          }),
          engine: engine,
        ),
        _Results(engine: engine, query: '', facts: confirmed),
      ],
    );
  }
}

/// A one-card summary of the facts the search used, with a way back.
class _ConfirmedFacts extends StatelessWidget {
  const _ConfirmedFacts({
    required this.facts,
    required this.snapshot,
    required this.onEdit,
  });
  final MatterFacts facts;
  final PublicRecordsSnapshot snapshot;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = facts;
    final parts = [
      if (f.caseNumber != null && f.caseNumber!.isNotEmpty) f.caseNumber!,
      if (f.subject != null) f.subject!.label,
      if (f.side != null)
        'for the ${f.side == RecordSide.petitioner ? 'petitioner' : 'respondent'}',
      if (f.stage != MatterStage.unknown) f.stage.label,
      if (f.benchJudgeId != null) 'before ${snapshot.judges[f.benchJudgeId!]}',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEARCHED WITH THE FACTS YOU CONFIRMED',
                  style: t.labelSmall?.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  parts.join(' · '),
                  style: t.titleMedium?.copyWith(color: AppColors.navy),
                ),
                if (f.issues.isNotEmpty || f.statutes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [...f.issues, ...f.statutes].join(' · '),
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit facts'),
          ),
        ],
      ),
    );
  }
}

/// Optional filters: nothing is required, the question alone is enough.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.snapshot,
    required this.subjectId,
    required this.benchJudgeId,
    required this.onSubject,
    required this.onBench,
  });
  final PublicRecordsSnapshot? snapshot;
  final String? subjectId;
  final int? benchJudgeId;
  final ValueChanged<String?> onSubject;
  final ValueChanged<int?> onBench;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Optional:', style: t.bodySmall?.copyWith(color: AppColors.muted)),
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<String?>(
            initialValue: subjectId,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Case type',
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('From my question'),
              ),
              for (final a in subjectAreas)
                DropdownMenuItem(value: a.id, child: Text(a.label)),
            ],
            onChanged: onSubject,
          ),
        ),
        if (snapshot != null)
          JudgePicker(
            snapshot: snapshot!,
            selected: benchJudgeId,
            onChanged: onBench,
          ),
      ],
    );
  }
}

class _UploadLead extends StatelessWidget {
  const _UploadLead({required this.reading, required this.onUpload});
  final bool reading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: reading ? null : onUpload,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(
              reading ? Icons.hourglass_top : Icons.upload_file,
              size: 36,
              color: AppColors.teal,
            ),
            const SizedBox(height: 10),
            Text(
              reading
                  ? 'Reading the document…'
                  : 'Choose a judgment or pleading (PDF or text)',
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            Text(
              'It is read in your browser and never uploaded. We match it against the knowledge layer and show who won similar matters.',
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryBox extends StatelessWidget {
  const _QueryBox({
    required this.controller,
    required this.onSubmit,
    required this.onChanged,
  });
  final TextEditingController controller;
  final void Function([String?]) onSubmit;
  final ValueChanged<String> onChanged;

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
              onChanged: onChanged,
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
    required this.service,
    required this.onClear,
  });
  final String name;
  final int chars;
  final bool service;
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
                  service
                      ? 'Read on this device (${fmtInt(chars)} characters). The text is also sent to the Brieflee '
                            'service for the AI reading; it is processed in memory and not stored.'
                      : 'Read on this device (${fmtInt(chars)} characters, not uploaded anywhere).',
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
    this.subjectId,
    this.benchJudgeId,
    this.facts,
  });
  final AskEngine engine;
  final String query;
  final SideChoice side;
  final String? subjectId;
  final int? benchJudgeId;

  /// Confirmed facts from an uploaded document; used instead of [query].
  final MatterFacts? facts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer = facts != null
        ? engine.askFacts(facts!)
        : engine.ask(
            query,
            side: side,
            subjectId: subjectId,
            benchJudgeId: benchJudgeId,
          );
    final snapshot = engine.snapshot;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    // The document's AI reading already carries a grounded answer.
    final generated = facts != null
        ? null
        : ref.watch(generatedAnswerProvider(query)).value;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnswerCard(answer: answer, generated: generated),
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
        if (facts == null) _ArchiveResults(query: query),
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

/// Results from the knowledge service's full archive (all its courts and
/// years), shown alongside the on-device results when the service is on.
class _ArchiveResults extends ConsumerWidget {
  const _ArchiveResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(knowledgeServiceProvider).configured) {
      return const SizedBox.shrink();
    }
    final t = Theme.of(context).textTheme;
    final a = ref.watch(serviceAskProvider(query));
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: SectionCard(
        title: 'Across the full archive',
        subtitle: 'The same question searched over the full text of every judgment the Brieflee service holds.',
        child: a.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (_, _) => const Text('The service did not respond.'),
          data: (m) {
            if (m == null) {
              return Text(
                'The service is not reachable right now; the results below are from this device.',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              );
            }
            final cases = (m['cases'] as List).cast<Map<String, dynamic>>();
            final counsel = (m['counsel'] as List).cast<Map<String, dynamic>>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtInt(m['similar_decisions'] as int)} similar decisions found. '
                  '${counsel.isEmpty ? 'Not enough decided outcomes to rank counsel.' : 'Counsel with the most favourable decided outcomes in them:'}',
                  style: t.bodyLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in counsel.take(10))
                      ActionChip(
                        avatar: const Icon(Icons.person_outline, size: 18),
                        label: Text(
                          '${c['name']} · ${c['favourable']} won, ${c['unfavourable']} lost of ${c['similar_matters']}',
                        ),
                        onPressed: () =>
                            context.go(Routes.counsel(q: c['name'] as String)),
                      ),
                  ],
                ),
                if (cases.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Most similar decisions',
                    style: t.titleMedium?.copyWith(color: AppColors.navy),
                  ),
                  const SizedBox(height: 4),
                  for (final c in cases.take(6))
                    InkWell(
                      onTap: c['pdf_url'] == null
                          ? null
                          : () => openPdf(
                              context,
                              Uri.parse(c['pdf_url'] as String),
                            ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 16,
                              color: AppColors.teal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${c['title']} · ${c['case_number']} · ${c['decision_date']} · ${c['outcome']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(
                                  color: AppColors.teal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (m['attribution'] != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    m['attribution'] as String,
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ],
            );
          },
        ),
      ),
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

class _CounselSection extends StatefulWidget {
  const _CounselSection({required this.answer, required this.snapshot});
  final AskAnswer answer;
  final PublicRecordsSnapshot snapshot;

  @override
  State<_CounselSection> createState() => _CounselSectionState();
}

class _CounselSectionState extends State<_CounselSection> {
  final Set<int> _compare = {};

  @override
  void didUpdateWidget(covariant _CounselSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.answer, widget.answer)) _compare.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final answer = widget.answer;
    final snapshot = widget.snapshot;
    final chosen = [
      for (final e in answer.counsel)
        if (_compare.contains(e.counselId)) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Counsel who won similar matters',
          style: t.headlineSmall?.copyWith(color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(
          'Ranked by a match score out of 100 built from decided outcomes in the similar decisions (favourable rate '
          'smoothed toward 50%), how close those matters are to yours, whether they acted for your side'
          '${answer.benchJudgeId != null ? ' and how often they appeared before your bench' : ''}. '
          'Open "Why this advocate" for the parts. At least ${AskEngine.minEligible} decided outcomes, at least one '
          'win and a favourable rate of 50% or more are needed to be listed. Government panel counsel are left out. '
          'This is evidence from past judgments, not a win probability, an endorsement or a prediction.',
          style: t.bodySmall?.copyWith(color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 10),
        if (answer.counsel.length > 1)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                chosen.length < 2
                    ? 'Tick two to four advocates to compare them.'
                    : '${chosen.length} selected.',
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
              FilledButton.tonalIcon(
                onPressed: chosen.length < 2
                    ? null
                    : () => showCounselComparison(
                        context,
                        answer: answer,
                        counsel: chosen,
                        snapshot: snapshot,
                      ),
                icon: const Icon(Icons.compare_arrows, size: 18),
                label: const Text('Compare'),
              ),
            ],
          ),
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
          _CounselRow(
            rank: i + 1,
            e: answer.counsel[i],
            snapshot: snapshot,
            benchJudgeId: answer.benchJudgeId,
            selected: _compare.contains(answer.counsel[i].counselId),
            onSelect: (v) => setState(() {
              final id = answer.counsel[i].counselId;
              if (v && _compare.length < 4) {
                _compare.add(id);
              } else {
                _compare.remove(id);
              }
            }),
          ),
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

class _CounselRow extends StatefulWidget {
  const _CounselRow({
    required this.rank,
    required this.e,
    required this.snapshot,
    required this.selected,
    required this.onSelect,
    this.benchJudgeId,
  });
  final int rank;
  final CounselEvidence e;
  final PublicRecordsSnapshot snapshot;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final int? benchJudgeId;

  @override
  State<_CounselRow> createState() => _CounselRowState();
}

class _CounselRowState extends State<_CounselRow> {
  bool _why = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = widget.e;
    final snapshot = widget.snapshot;
    void sheet(String what, List<int> idx, {String? note}) => showRecordsSheet(
      context,
      snapshot: snapshot,
      title: '${e.name}: $what',
      note: note,
      recordIndexes: idx,
      forCounsel: e.counselId,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Text(
                  '${widget.rank}',
                  style: t.headlineSmall?.copyWith(color: AppColors.gold),
                ),
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: widget.selected,
                  onChanged: (v) => widget.onSelect(v ?? false),
                ),
              ],
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
                  'Acted for petitioners ${e.petitionerSide}×, respondents ${e.respondentSide}× in these matters'
                  '${widget.benchJudgeId != null ? ' · ${e.benchAppearances} appearances before ${snapshot.judges[widget.benchJudgeId!]}' : ''}',
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
                      onTap: () => sheet('favourable outcomes', e.favourable),
                    ),
                    EvidenceNumber(
                      value: '${e.unfavourable.length}',
                      label: 'unfavourable',
                      color: AppColors.unfavorable,
                      onTap: () =>
                          sheet('unfavourable outcomes', e.unfavourable),
                    ),
                    EvidenceNumber(
                      value: '${e.notEligible.length}',
                      label: 'not counted',
                      onTap: () => sheet(
                        'not counted as outcomes',
                        e.notEligible,
                        note: 'Settled, withdrawn, interim, mixed or unclear outcomes. They are shown but not counted.',
                      ),
                    ),
                    EvidenceNumber(
                      value: '${e.similar.length}',
                      label: 'similar matters',
                      onTap: () => sheet('similar matters', e.similar),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => setState(() => _why = !_why),
                  icon: Icon(
                    _why ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: const Text('Why this advocate'),
                ),
                if (_why) _WhyBreakdown(e: e, bench: widget.benchJudgeId),
              ],
            ),
          ),
          SizedBox(
            width: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  e.score.round().toString(),
                  style: t.headlineMedium?.copyWith(color: AppColors.navy),
                ),
                Text(
                  'match score',
                  style: t.labelSmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                _ConfidenceTag(e.confidence),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceTag extends StatelessWidget {
  const _ConfidenceTag(this.level);
  final String level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'High' => AppColors.favorable,
      'Medium' => AppColors.gold,
      _ => AppColors.muted,
    };
    return Tooltip(
      message:
          'Evidence confidence: how many decided outcomes the score rests on '
          '(High 15+, Medium 6+, Low fewer). Separate from the match score.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$level evidence',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

/// The parts of the match score, each already weighted.
class _WhyBreakdown extends StatelessWidget {
  const _WhyBreakdown({required this.e, this.bench});
  final CounselEvidence e;
  final int? bench;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = [
      (
        'Outcomes',
        e.rateComponent,
        bench == null ? 45.0 : 40.0,
        '${e.favourable.length} favourable of ${e.eligible} decided; ${(e.smoothedRate * 100).round()}% after smoothing toward 50%',
      ),
      (
        'Similarity',
        e.relevanceComponent,
        bench == null ? 35.0 : 30.0,
        'How closely their ${e.similar.length} matters match yours',
      ),
      (
        'Your side',
        e.sideComponent,
        bench == null ? 20.0 : 15.0,
        'Share of these matters where they acted for your side',
      ),
      if (bench != null)
        (
          'Your bench',
          e.benchComponent,
          15.0,
          '${e.benchAppearances} appearances before this judge in all records (full marks at 5)',
        ),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, value, max, note) in rows) ...[
            Row(
              children: [
                SizedBox(width: 92, child: Text(name, style: t.labelLarge)),
                Expanded(
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : (value / max).clamp(0, 1),
                    minHeight: 6,
                    color: AppColors.teal,
                    backgroundColor: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${value.toStringAsFixed(1)} / ${max.round()}',
                    textAlign: TextAlign.right,
                    style: t.labelMedium,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 92, bottom: 8, top: 2),
              child: Text(
                note,
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
          ],
          Text(
            'Match score ${e.score.round()} = the parts above. Every count links to the judgments behind it.',
            style: t.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Side-by-side comparison of two to four advocates for this matter.
void showCounselComparison(
  BuildContext context, {
  required AskAnswer answer,
  required List<CounselEvidence> counsel,
  required PublicRecordsSnapshot snapshot,
}) {
  final bench = answer.benchJudgeId;
  final rows = <(String, String Function(CounselEvidence))>[
    ('Match score', (e) => '${e.score.round()}'),
    ('Evidence confidence', (e) => e.confidence),
    ('Favourable', (e) => '${e.favourable.length}'),
    ('Unfavourable', (e) => '${e.unfavourable.length}'),
    ('Not counted', (e) => '${e.notEligible.length}'),
    ('Similar matters', (e) => '${e.similar.length}'),
    ('Smoothed favourable rate', (e) => '${(e.smoothedRate * 100).round()}%'),
    (
      'For petitioner / respondent',
      (e) => '${e.petitionerSide} / ${e.respondentSide}',
    ),
    if (bench != null)
      ('Before ${snapshot.judges[bench]}', (e) => '${e.benchAppearances}'),
  ];
  showDialog<void>(
    context: context,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      return AlertDialog(
        title: const Text('Compare advocates'),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 24,
              columns: [
                const DataColumn(label: Text('')),
                for (final e in counsel)
                  DataColumn(
                    label: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(Routes.recordCounsel(e.counselId));
                      },
                      child: Text(
                        e.name,
                        style: t.titleSmall?.copyWith(
                          color: AppColors.navy,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
              rows: [
                for (final (label, value) in rows)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          label,
                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ),
                      for (final e in counsel) DataCell(Text(value(e))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
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

/// Issues found in an uploaded document by the knowledge service (Claude),
/// each linked to similar decisions. Shown only when the service is connected.
class _ServiceAnalysis extends ConsumerWidget {
  const _ServiceAnalysis({required this.request, required this.engine});

  /// The JSON request body for /v1/analyze.
  final String request;
  final AskEngine engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(knowledgeServiceProvider).configured) {
      return const SizedBox.shrink();
    }
    final t = Theme.of(context).textTheme;
    final a = ref.watch(documentAnalysisProvider(request));
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: SectionCard(
        title: 'AI reading of your document',
        subtitle: 'The AI split the document into passages, found the issues it turns on, and searched the knowledge layer for each one.',
        child: a.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (_, _) => const Text('The analysis service did not respond.'),
          data: (m) {
            if (m == null) {
              return Text(
                'The analysis service is not reachable right now; the on-device results below still apply.',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              );
            }
            final issues = (m['issues'] as List).cast<Map<String, dynamic>>();
            final counsel = (m['counsel'] as List).cast<Map<String, dynamic>>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m['summary'] != null) ...[
                  Text(m['summary'] as String, style: t.bodyLarge),
                  const SizedBox(height: 6),
                  Text(
                    [
                      '${m['chunks']} passages read',
                      if (m['client_side'] == 'p')
                        'you appear to act for the petitioner',
                      if (m['client_side'] == 'r')
                        'you appear to act for the respondent',
                      '${m['similar_decisions']} similar decisions',
                    ].join(' · '),
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final (i, issue) in issues.indexed) ...[
                  Text(
                    '${i + 1}. ${issue['title']}',
                    style: t.titleMedium?.copyWith(color: AppColors.navy),
                  ),
                  if ((issue['statutes'] as List).isNotEmpty)
                    Text(
                      (issue['statutes'] as List).join('; '),
                      style: t.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  const SizedBox(height: 4),
                  for (final c
                      in (issue['cases'] as List)
                          .cast<Map<String, dynamic>>()
                          .take(3))
                    _ServiceCaseLink(card: c, engine: engine),
                  const SizedBox(height: 12),
                ],
                if (counsel.isNotEmpty) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Counsel who won these matters',
                    style: t.titleMedium?.copyWith(color: AppColors.navy),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in counsel.take(8))
                        ActionChip(
                          avatar: const Icon(Icons.person_outline, size: 18),
                          label: Text(
                            '${c['name']} · ${c['favourable']} won, ${c['unfavourable']} lost',
                          ),
                          onPressed: () => context.go(
                            Routes.counsel(q: c['name'] as String),
                          ),
                        ),
                    ],
                  ),
                ],
                if (m['answer'] != null) ...[
                  const SizedBox(height: 16),
                  Text(m['answer'] as String, style: t.bodyMedium),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceCaseLink extends StatelessWidget {
  const _ServiceCaseLink({required this.card, required this.engine});
  final Map<String, dynamic> card;
  final AskEngine engine;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final id = card['id'] as String;
    final local = engine.snapshot.byId(id);
    return InkWell(
      onTap: local == null ? null : () => context.go(Routes.record(id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              size: 16,
              color: AppColors.teal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${card['title']} · ${card['case_number']} · ${card['decision_date']} · ${card['outcome']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(
                  color: local == null ? AppColors.muted : AppColors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
