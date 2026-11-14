import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../application/court_providers.dart';

class CourtExplorerScreen extends ConsumerStatefulWidget {
  const CourtExplorerScreen({super.key});

  @override
  ConsumerState<CourtExplorerScreen> createState() =>
      _CourtExplorerScreenState();
}

class _CourtExplorerScreenState extends ConsumerState<CourtExplorerScreen> {
  CourtType? _type;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final courts = ref.watch(courtsProvider);
    return PageBody(
      children: [
        const PageHeader(
          title: 'Court explorer',
          subtitle: 'Courts, tribunals, jurisdictions and case categories',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search courts or categories',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v.toLowerCase()),
              ),
            ),
            ChoiceChip(
              label: const Text('All'),
              selected: _type == null,
              onSelected: (_) => setState(() => _type = null),
            ),
            for (final t in CourtType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AsyncView<List<Court>>(
          value: courts,
          onRetry: () => ref.invalidate(courtsProvider),
          builder: (list) {
            final filtered = list.where((c) {
              if (_type != null && c.type != _type) return false;
              if (_q.isEmpty) return true;
              return c.name.toLowerCase().contains(_q) ||
                  c.caseCategories.any((x) => x.toLowerCase().contains(_q));
            }).toList();
            if (filtered.isEmpty) {
              return const EmptyState(
                icon: Icons.account_balance_outlined,
                title: 'No courts match',
                message: 'Try a different search or court type.',
              );
            }
            return LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth > 900 ? 2 : 1;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final court in filtered)
                      SizedBox(
                        width: (c.maxWidth - 14 * (cols - 1)) / cols,
                        child: _CourtCard(court: court),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});
  final Court court;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pilot = court.support == CourtSupport.pilot;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.court(court.id)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: pilot ? AppColors.navy : AppColors.border,
                    child: Text(
                      court.shortName.substring(0, 1),
                      style: TextStyle(
                        color: pilot ? AppColors.gold : AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(court.name, style: t.titleMedium),
                        Text(
                          court.type.label,
                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Pill(
                    label: court.support.label,
                    color: pilot ? AppColors.teal : AppColors.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(court.jurisdiction, style: t.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cat in court.caseCategories)
                    Chip(
                      label: Text(cat, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (!pilot) ...[
                const SizedBox(height: 10),
                Text(
                  'Coverage planned after the Delhi High Court pilot.',
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
