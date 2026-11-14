import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/api/brieflee_api.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../court_explorer/application/court_providers.dart';
import '../../document_upload/domain/upload_policy.dart';
import '../../document_upload/presentation/document_picker_panel.dart';
import '../application/matter_providers.dart';

/// Guided case intake: describe, upload or enter a case number.
class NewMatterScreen extends ConsumerStatefulWidget {
  const NewMatterScreen({super.key, this.initialMode, this.initialText});
  final String? initialMode;
  final String? initialText;

  @override
  ConsumerState<NewMatterScreen> createState() => _NewMatterScreenState();
}

class _NewMatterScreenState extends ConsumerState<NewMatterScreen> {
  late IntakeMode _mode;
  final _title = TextEditingController();
  late final TextEditingController _description;
  final _caseNumber = TextEditingController();
  String _courtId = 'dhc';
  List<PendingUpload> _files = [];
  bool _consent = false;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = IntakeMode.values.firstWhere(
      (m) => m.name == widget.initialMode,
      orElse: () => IntakeMode.describe,
    );
    _description = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _caseNumber.dispose();
    super.dispose();
  }

  String? _validate() {
    if (!_consent) return 'Please confirm consent to process this matter.';
    switch (_mode) {
      case IntakeMode.describe:
        if (_description.text.trim().length < 20) {
          return 'Add a little more detail (at least 20 characters).';
        }
      case IntakeMode.upload:
        if (_files.isEmpty) return 'Choose at least one document.';
      case IntakeMode.caseNumber:
        if (_caseNumber.text.trim().isEmpty) return 'Enter the case number.';
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    setState(() => _error = err);
    if (err != null) return;

    setState(() {
      _busy = true;
      _status = 'Creating matter…';
    });
    try {
      final repo = ref.read(matterRepositoryProvider);
      final title = _title.text.trim().isNotEmpty
          ? _title.text.trim()
          : switch (_mode) {
              IntakeMode.caseNumber => _caseNumber.text.trim(),
              IntakeMode.upload => _files.first.fileName,
              IntakeMode.describe =>
                _description.text.trim().split(RegExp(r'[.\n]')).first,
            };
      final matter = await repo.create(
        CreateMatterRequest(
          title: title.length > 70 ? '${title.substring(0, 70)}…' : title,
          intakeMode: _mode,
          description: _description.text,
          caseNumber: _caseNumber.text,
          courtId: _courtId,
        ),
      );
      for (var i = 0; i < _files.length; i++) {
        setState(() => _status = 'Uploading ${i + 1} of ${_files.length}…');
        final f = _files[i];
        await repo.addDocument(
          matter.id,
          fileName: f.fileName,
          sizeBytes: f.sizeBytes,
          kind: f.kind,
        );
      }
      refreshMatters(ref);
      if (mounted) context.go(Routes.analysis(matter.id));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final courts = ref.watch(courtsProvider);

    return PageBody(
      maxWidth: 820,
      children: [
        const PageHeader(
          title: 'New matter',
          subtitle:
              'Tell us about the matter. You will review and edit '
              'everything we extract before any search runs.',
        ),
        SegmentedButton<IntakeMode>(
          segments: const [
            ButtonSegment(
              value: IntakeMode.describe,
              icon: Icon(Icons.edit_note),
              label: Text('Describe'),
            ),
            ButtonSegment(
              value: IntakeMode.upload,
              icon: Icon(Icons.upload_file),
              label: Text('Upload'),
            ),
            ButtonSegment(
              value: IntakeMode.caseNumber,
              icon: Icon(Icons.tag),
              label: Text('Case no.'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() {
            _mode = s.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: _mode.label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Matter name (optional)',
                  hintText: 'e.g. Snack brand trademark dispute',
                ),
              ),
              const SizedBox(height: 14),
              if (_mode == IntakeMode.caseNumber) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _caseNumber,
                        decoration: const InputDecoration(
                          labelText: 'Case number',
                          hintText: 'e.g. CS(COMM) 512/2026',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    Text('Try a demo listing:', style: t.bodySmall),
                    for (final n in const [
                      'CS(COMM) 512/2026',
                      'FAO(OS)(COMM) 77/2026',
                      'OMP(I)(COMM) 140/2026',
                    ])
                      ActionChip(
                        label: Text(n, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => _caseNumber.text = n),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              courts.when(
                data: (list) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _courtId,
                  decoration: const InputDecoration(
                    labelText: 'Court or tribunal',
                  ),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(
                        value: c.id,
                        enabled: c.support == CourtSupport.pilot,
                        child: Text(
                          c.support == CourtSupport.pilot
                              ? c.name
                              : '${c.name} (planned)',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _courtId = v ?? _courtId),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Courts unavailable: $e'),
              ),
              const SizedBox(height: 14),
              if (_mode == IntakeMode.upload) ...[
                DocumentPickerPanel(
                  files: _files,
                  onChanged: (f) => setState(() => _files = f),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _description,
                minLines: _mode == IntakeMode.describe ? 6 : 3,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: _mode == IntakeMode.describe
                      ? 'What happened, and what do you need?'
                      : 'Anything else we should know? (optional)',
                  alignLabelWithHint: true,
                  hintText:
                      'Plain language is fine. Avoid names of private individuals '
                      'unless needed.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I consent to Brieflee processing this matter to '
            'find relevant counsel. I can delete it and its documents at any time.',
          ),
          subtitle: const Text(
            'Personal details are redacted before any external AI processing.',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.unfavorable),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (_status != null)
              Expanded(
                child: Text(
                  _status!,
                  style: const TextStyle(color: AppColors.muted),
                ),
              )
            else
              const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('Analyze matter'),
            ),
          ],
        ),
      ],
    );
  }
}
