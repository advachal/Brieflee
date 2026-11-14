import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/case_type_subjects.dart';
import '../../../core/public_records/matter_facts.dart';
import '../../../core/public_records/public_records.dart';
import '../../../core/widgets/common.dart';

/// The facts read from an uploaded document, for the user to check and
/// correct before anything is recommended.
class MatterFactsPanel extends StatefulWidget {
  const MatterFactsPanel({
    super.key,
    required this.facts,
    required this.snapshot,
    required this.onConfirm,
    this.aiStatus,
  });

  final MatterFacts facts;
  final PublicRecordsSnapshot snapshot;
  final ValueChanged<MatterFacts> onConfirm;

  /// A line about the AI reading (in progress, done, unavailable).
  final String? aiStatus;

  @override
  State<MatterFactsPanel> createState() => _MatterFactsPanelState();
}

class _MatterFactsPanelState extends State<MatterFactsPanel> {
  late MatterFacts f = widget.facts.copy();
  final _newStatute = TextEditingController();
  late List<TextEditingController> _issues = _issueControllers();

  List<TextEditingController> _issueControllers() => [
    for (final i in f.issues) TextEditingController(text: i),
  ];

  @override
  void didUpdateWidget(covariant MatterFactsPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.facts, widget.facts)) {
      f = widget.facts.copy();
      for (final c in _issues) {
        c.dispose();
      }
      _issues = _issueControllers();
    }
  }

  @override
  void dispose() {
    _newStatute.dispose();
    for (final c in _issues) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    f.issues = [
      for (final c in _issues)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    widget.onConfirm(f.copy());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = widget.snapshot;
    final compact = MediaQuery.sizeOf(context).width < 720;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: t.labelSmall?.copyWith(
          color: AppColors.gold,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    Widget field(String name, String? value, ValueChanged<String> onChanged) =>
        TextFormField(
          initialValue: value,
          onChanged: (v) => onChanged(v.trim().isEmpty ? '' : v.trim()),
          decoration: InputDecoration(labelText: name, isDense: true),
        );

    final pairs = <Widget>[
      field('Case number', f.caseNumber, (v) => f.caseNumber = v),
      field('Court', f.court, (v) => f.court = v),
      field('Petitioner / appellant', f.petitioner, (v) => f.petitioner = v),
      field('Respondent', f.respondent, (v) => f.respondent = v),
    ];

    return SectionCard(
      title: 'Check the facts of your matter',
      subtitle:
          'Read from your document${f.source == 'device' ? ' on this device' : ' by ${f.source}'}. Correct anything that is wrong: '
          'the search uses exactly what you confirm here.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.aiStatus != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.aiStatus!,
                style: t.bodySmall?.copyWith(color: AppColors.teal),
              ),
            ),
          if (f.summary != null) ...[
            Text(f.summary!, style: t.bodyLarge),
            const SizedBox(height: 4),
          ],
          label('The case'),
          if (compact)
            for (final w in pairs) ...[w, const SizedBox(height: 10)]
          else
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [for (final w in pairs) SizedBox(width: 330, child: w)],
            ),
          label('Case type'),
          DropdownButtonFormField<String?>(
            initialValue: f.subjectId,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('Not sure')),
              for (final a in subjectAreas)
                DropdownMenuItem(value: a.id, child: Text(a.label)),
            ],
            onChanged: (v) => setState(() => f.subjectId = v),
          ),
          label('You act for'),
          SegmentedButton<RecordSide?>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: RecordSide.petitioner,
                label: Text('Petitioner'),
              ),
              ButtonSegment(
                value: RecordSide.respondent,
                label: Text('Respondent'),
              ),
              ButtonSegment(value: null, label: Text('Not sure')),
            ],
            selected: {f.side},
            onSelectionChanged: (v) => setState(() => f.side = v.first),
          ),
          label('Stage now'),
          DropdownButtonFormField<MatterStage>(
            initialValue: f.stage,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final st in MatterStage.values)
                DropdownMenuItem(value: st, child: Text(st.label)),
            ],
            onChanged: (v) => setState(() => f.stage = v!),
          ),
          label('Bench'),
          Text(
            f.decidingJudgeNames.isEmpty
                ? 'No deciding judge found in the document.'
                : 'This document was decided by ${f.decidingJudgeNames.join(' and ')}. '
                      'That is not necessarily the judge your matter is listed before now.',
            style: t.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          JudgePicker(
            snapshot: s,
            selected: f.benchJudgeId,
            suggestions: f.decidingJudgeIds,
            suggestionPrefix: 'Still before',
            onChanged: (id) => setState(() => f.benchJudgeId = id),
          ),
          label('Statutes'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final st in f.statutes)
                InputChip(
                  label: Text(st),
                  onDeleted: () => setState(() => f.statutes.remove(st)),
                ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _newStatute,
                  decoration: const InputDecoration(
                    hintText: 'Add, e.g. s.9 Arbitration and Conciliation Act',
                    isDense: true,
                  ),
                  onSubmitted: (v) => setState(() {
                    if (v.trim().isNotEmpty) f.statutes.add(v.trim());
                    _newStatute.clear();
                  }),
                ),
              ),
            ],
          ),
          label('Issues to search for'),
          for (var i = 0; i < _issues.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _issues[i],
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '${i + 1}.  ',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove issue',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _issues.removeAt(i).dispose();
                    }),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _issues.add(TextEditingController())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add an issue'),
            ),
          ),
          label('Relief sought'),
          field('Relief', f.relief, (v) => f.relief = v),
          if (f.counsel.isNotEmpty) ...[
            label('Counsel named in the document'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in f.counsel)
                  ActionChip(
                    avatar: Icon(
                      c.counselId == null
                          ? Icons.person_off_outlined
                          : Icons.person_outline,
                      size: 18,
                    ),
                    label: Text(
                      '${c.name} · ${c.side == RecordSide.petitioner ? 'petitioner' : 'respondent'}',
                    ),
                    onPressed: c.counselId == null
                        ? null
                        : () => context.go(Routes.recordCounsel(c.counselId!)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Names with a person icon match an advocate in the records (by spelling); tap to see their record.',
              style: t.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Find matching advocates'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks the judge a matter is listed before (optional).
class JudgePicker extends StatelessWidget {
  const JudgePicker({
    super.key,
    required this.snapshot,
    required this.selected,
    required this.onChanged,
    this.suggestions = const [],
    this.suggestionPrefix = '',
  });
  final PublicRecordsSnapshot snapshot;
  final int? selected;
  final List<int> suggestions;
  final String suggestionPrefix;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final names = snapshot.judges;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (selected != null)
          InputChip(
            avatar: const Icon(Icons.gavel, size: 16),
            label: Text('Listed before ${names[selected!]}'),
            onDeleted: () => onChanged(null),
          )
        else ...[
          for (final j in suggestions)
            ActionChip(
              avatar: const Icon(Icons.gavel_outlined, size: 16),
              label: Text('$suggestionPrefix ${names[j]}'),
              onPressed: () => onChanged(j),
            ),
          SizedBox(
            width: 300,
            child: Autocomplete<int>(
              optionsBuilder: (v) {
                final q = v.text.toLowerCase().trim();
                if (q.length < 2) return const Iterable<int>.empty();
                return [
                  for (var i = 0; i < names.length; i++)
                    if (names[i].toLowerCase().contains(q)) i,
                ].take(8);
              },
              displayStringForOption: (i) => names[i],
              onSelected: onChanged,
              fieldViewBuilder: (context, controller, focus, onSubmit) =>
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: const InputDecoration(
                      hintText: 'Judge it is listed before (optional)',
                      isDense: true,
                      prefixIcon: Icon(Icons.gavel_outlined, size: 18),
                    ),
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
