import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/public_records/directory.dart';
import '../../../shared/utilities/formatters.dart';
import '../../ask/application/ask_providers.dart';
import '../../ask/presentation/record_widgets.dart';

/// Search field with suggestions that update on every keystroke: subjects,
/// counsel, judges and cases from the real records. Enter runs a full Ask.
class LiveSearchField extends ConsumerStatefulWidget {
  const LiveSearchField({
    super.key,
    required this.onAsk,
    this.hint = 'Search a matter, advocate, judge or case number',
    this.large = true,
  });

  final void Function(String query) onAsk;
  final String hint;
  final bool large;

  @override
  ConsumerState<LiveSearchField> createState() => _LiveSearchFieldState();
}

class _LiveSearchFieldState extends ConsumerState<LiveSearchField> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _q = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  void _ask() {
    final q = _c.text.trim();
    if (q.isNotEmpty) widget.onAsk(q);
  }

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(directoryProvider);
    final results = _q.length < 2
        ? QuickResults.empty
        : dir.maybeWhen(
            data: (d) => d.quickSearch(_q),
            orElse: () => QuickResults.empty,
          );
    final loading = _q.length >= 2 && dir.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(22, 6, 6, 6),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _c,
                  focusNode: _focus,
                  onChanged: _changed,
                  onSubmitted: (_) => _ask(),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: widget.large ? 17 : 16),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              FilledButton(onPressed: _ask, child: const Text('Ask')),
            ],
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_q.length >= 2 && !loading)
          _Suggestions(
            query: _q,
            results: results,
            onAsk: () => widget.onAsk(_q),
          ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.query,
    required this.results,
    required this.onAsk,
  });
  final String query;
  final QuickResults results;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget header(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        s.toUpperCase(),
        style: t.labelSmall?.copyWith(
          color: AppColors.gold,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.teal),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.titleSmall?.copyWith(color: AppColors.navy),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: AppColors.muted),
            ),
      onTap: onTap,
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            icon: Icons.auto_awesome_outlined,
            title: 'Find counsel who won matters like “$query”',
            subtitle: 'Full answer from the knowledge layer',
            onTap: onAsk,
          ),
          if (results.subjects.isNotEmpty) ...[
            header('Subjects'),
            for (final s in results.subjects)
              row(
                icon: Icons.category_outlined,
                title: s.subject.label,
                subtitle: '${fmtInt(s.count)} decisions · see top counsel',
                onTap: () => context.go(Routes.counsel(subject: s.subject.id)),
              ),
          ],
          if (results.counsel.isNotEmpty) ...[
            header('Advocates'),
            for (final h in results.counsel)
              row(
                icon: Icons.person_outline,
                title: h.stat.name,
                subtitle: _counselLine(h.stat),
                onTap: () => context.go(Routes.recordCounsel(h.stat.id)),
              ),
          ],
          if (results.judges.isNotEmpty) ...[
            header('Judges'),
            for (final h in results.judges)
              row(
                icon: Icons.gavel_outlined,
                title: h.stat.name,
                subtitle: '${fmtInt(h.stat.decisions)} decisions',
                onTap: () => context.go(Routes.recordJudge(h.stat.id)),
              ),
          ],
          if (results.cases.isNotEmpty) ...[
            header('Cases'),
            for (final h in results.cases)
              row(
                icon: Icons.description_outlined,
                title: h.record.title,
                subtitle: formatDate(h.record.date),
                onTap: () => context.go(Routes.record(h.record.id)),
              ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

String _counselLine(CounselStat c) {
  final parts = <String>['${fmtInt(c.appearances)} appearances'];
  if (c.decided > 0) parts.add('${c.wins} won, ${c.losses} lost');
  if (c.isGovernment) parts.add('mostly government counsel');
  return parts.join(' · ');
}

String counselSummaryLine(CounselStat c) => _counselLine(c);
