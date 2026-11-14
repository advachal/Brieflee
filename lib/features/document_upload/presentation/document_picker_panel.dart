import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../shared/utilities/formatters.dart';
import '../domain/upload_policy.dart';

/// Lets the user choose case documents. In this prototype only the file name
/// and size are read; file contents never leave the device.
class DocumentPickerPanel extends StatefulWidget {
  const DocumentPickerPanel({
    super.key,
    required this.files,
    required this.onChanged,
  });

  final List<PendingUpload> files;
  final ValueChanged<List<PendingUpload>> onChanged;

  @override
  State<DocumentPickerPanel> createState() => _DocumentPickerPanelState();
}

class _DocumentPickerPanelState extends State<DocumentPickerPanel> {
  final List<String> _errors = [];
  bool _picking = false;

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _errors.clear();
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: UploadPolicy.allowedExtensions,
      );
      final next = [...widget.files];
      for (final f in picked) {
        final size = await f.length() ?? 0;
        final err = UploadPolicy.validate(f.name, size);
        if (err != null) {
          _errors.add(err);
        } else if (next.length >= UploadPolicy.maxFiles) {
          _errors.add('Up to ${UploadPolicy.maxFiles} files per matter.');
          break;
        } else {
          next.add(
            PendingUpload(
              fileName: f.name,
              sizeBytes: size,
              kind: UploadPolicy.guessKind(f.name),
            ),
          );
        }
      }
      widget.onChanged(next);
    } catch (e) {
      _errors.add('Could not open the file picker on this device.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _addSample() {
    widget.onChanged([
      ...widget.files,
      PendingUpload(
        fileName: 'sample_plaint_trademark_demo.pdf',
        sizeBytes: 482113,
        kind: DocumentKind.petition,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _picking ? null : _pick,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.tealSoft.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.teal.withValues(alpha: 0.4),
                width: 1.4,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _picking ? Icons.hourglass_top : Icons.cloud_upload_outlined,
                  size: 34,
                  color: AppColors.teal,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose petitions, judgments, orders or notices',
                  style: t.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'PDF, Word, text or images · up to 25 MB each',
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addSample,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Add a sample document (demo)'),
          ),
        ),
        for (final e in _errors)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              e,
              style: const TextStyle(color: AppColors.unfavorable),
            ),
          ),
        if (widget.files.isNotEmpty) const SizedBox(height: 8),
        for (final f in widget.files)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    color: AppColors.navy,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.fileName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          formatBytes(f.sizeBytes),
                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<DocumentKind>(
                    value: f.kind,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final k in DocumentKind.values)
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (k) {
                      setState(() => f.kind = k ?? f.kind);
                      widget.onChanged([...widget.files]);
                    },
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => widget.onChanged(
                      widget.files.where((x) => x != f).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.lock_outline, size: 15, color: AppColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Prototype: only the file name and size are recorded; contents '
                'never leave your device. Production uploads are encrypted, '
                'malware-scanned and deletable at any time.',
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
