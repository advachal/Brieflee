import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/constants/breakpoints.dart';
import '../../ask/application/ask_providers.dart';
import '../../ask/presentation/record_widgets.dart';
import '../../directory/presentation/live_search.dart';

/// Landing page. Editorial layout: a large centred statement, one search
/// field, then full-width sections separated by whitespace and hairlines.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _ask(String q) => context.go(Routes.ask(q));

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < Breakpoints.compact;
    final pad = compact ? 20.0 : 48.0;

    return ListView(
      children: [
        _Section(
          color: AppColors.surface,
          padding: EdgeInsets.fromLTRB(
            pad,
            compact ? 48 : 112,
            pad,
            compact ? 56 : 112,
          ),
          child: _Hero(onAsk: _ask, compact: compact),
        ),
        _Section(
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: compact ? 56 : 96,
          ),
          child: const _TopAdvocates(),
        ),
        _Section(
          color: AppColors.surface,
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: compact ? 56 : 104,
          ),
          child: const _HowItWorks(),
        ),
        _Section(
          color: AppColors.navy,
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: compact ? 56 : 104,
          ),
          child: const _Principles(),
        ),
        _Section(
          color: AppColors.surface,
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: compact ? 56 : 96,
          ),
          child: const _Status(),
        ),
        _Section(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 40),
          child: Text(
            AppStrings.outcomeDisclaimer,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, required this.padding, this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    color: color,
    padding: padding,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: child,
      ),
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {this.color = AppColors.gold});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 13,
      letterSpacing: 2.2,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onAsk, required this.compact});
  final void Function(String) onAsk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        const _Eyebrow('Evidence-based counsel discovery'),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Text(
            'Find counsel by evidence,\nnot guesswork.',
            textAlign: TextAlign.center,
            style: (compact ? t.displaySmall : t.displayLarge)?.copyWith(
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Start typing: a dispute, an advocate, a judge or a case number. Results come '
            'live from 109,341 real Delhi High Court decisions, and every number opens '
            'the judgments behind it.',
            textAlign: TextAlign.center,
            style: t.bodyLarge?.copyWith(
              color: AppColors.muted,
              fontSize: compact ? 18 : 21,
            ),
          ),
        ),
        SizedBox(height: compact ? 32 : 48),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: LiveSearchField(
            onAsk: onAsk,
            hint: compact
                ? 'Matter, advocate, judge or case no.'
                : 'e.g. section 34 arbitral award, or an advocate\'s name',
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 28,
          runSpacing: 8,
          children: [
            _ChevronLink('Upload a judgment', () => context.go(Routes.upload)),
            _ChevronLink(
              'Browse advocates',
              () => context.go(Routes.counsel()),
            ),
            _ChevronLink('Browse judges', () => context.go(Routes.judges())),
          ],
        ),
      ],
    );
  }
}

/// Advocates with the best decided record, computed live from the records.
class _TopAdvocates extends ConsumerWidget {
  const _TopAdvocates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final dir = ref.watch(directoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('From the records', color: AppColors.teal),
        const SizedBox(height: 16),
        Text(
          'Advocates with the strongest decided record',
          style: (compact ? t.headlineMedium : t.displaySmall)?.copyWith(
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Commercial, arbitration and IP judgments read in full, with at least five clear wins or losses. '
          'Rates are smoothed toward 50% so a short record cannot top the list. Government counsel are left out.',
          style: t.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        dir.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text('$e'),
          data: (d) {
            final top = d.topCounsel(minDecided: 5).take(8).toList();
            return Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  InkWell(
                    onTap: () => context.go(Routes.recordCounsel(top[i].id)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${i + 1}',
                              style: t.titleLarge?.copyWith(
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  top[i].name,
                                  style: t.titleMedium?.copyWith(
                                    color: AppColors.navy,
                                  ),
                                ),
                                Text(
                                  counselSummaryLine(top[i]),
                                  style: t.bodySmall?.copyWith(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _ChevronLink(
                    'See all ${fmtInt(d.counsel.where((c) => c.appearances > 0).length)} advocates',
                    () => context.go(Routes.counsel()),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChevronLink extends StatelessWidget {
  const _ChevronLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Text(
        '$label  ›',
        style: const TextStyle(
          color: AppColors.teal,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (
      'Describe the matter',
      'Type it in plain language, or upload a judgment. The document is read in your browser and never leaves it.',
    ),
    (
      'We find similar decisions',
      'Your words are matched against the knowledge layer: statutes, key terms and parties from 13,241 judgments read in full.',
    ),
    (
      'We read how they ended',
      'Only clear wins and losses count. Settlements, withdrawals, interim orders and arbitrator appointments do not.',
    ),
    (
      'You see the counsel who won',
      'Ranked by their decided record in those matters. Every number opens the judgments behind it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 860;
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('How it works', color: AppColors.teal),
            const SizedBox(height: 16),
            Text(
              'From a plain-language brief to verifiable recommendations.',
              style: (narrow ? t.headlineMedium : t.displaySmall)?.copyWith(
                color: AppColors.navy,
              ),
            ),
          ],
        );
        final list = Column(
          children: [
            for (var i = 0; i < _steps.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.navy, width: 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        '0${i + 1}',
                        style: t.headlineSmall?.copyWith(color: AppColors.gold),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _steps[i].$1,
                            style: t.titleLarge?.copyWith(
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _steps[i].$2,
                            style: t.bodyLarge?.copyWith(
                              color: AppColors.muted,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        if (narrow) {
          return Column(children: [intro, const SizedBox(height: 36), list]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: intro),
            const SizedBox(width: 72),
            Expanded(flex: 7, child: list),
          ],
        );
      },
    );
  }
}

class _Principles extends StatelessWidget {
  const _Principles();

  static const _items = [
    (
      'No paid placement',
      'No advertisements, sponsored ranks or popularity scores.',
    ),
    (
      'Nothing invented',
      'No fabricated advocates, judgments, citations or statistics.',
    ),
    (
      'Honest about gaps',
      'When evidence is thin, we say so instead of forcing a ranking.',
    ),
    (
      'No insinuation',
      'Judge-specific experience is documented history, never influence.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('Our standard'),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Text(
            'Every recommendation is explainable. Every factual claim is verifiable.',
            style: (compact ? t.headlineMedium : t.displayMedium)?.copyWith(
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 56),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 2 : 1);
            const gap = 32.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: 36,
              children: [
                for (final p in _items)
                  SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.only(top: 18),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.gold, width: 2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.$1,
                            style: t.titleLarge?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            p.$2,
                            style: t.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const rows = [
      ('Court', 'Delhi High Court, decisions from 2023 to 2025'),
      ('Decisions indexed', '109,341 orders and judgments'),
      (
        'Read in full',
        '13,241 commercial, arbitration and IP judgments, with outcomes',
      ),
      ('Source', 'eCourts judgments portal via AWS Open Data (CC BY 4.0)'),
      ('Coming next', 'More courts and subjects, using the same pipeline'),
      (
        'Limits',
        'Counsel names are parsed from judgments and matched by spelling; verify before relying on them',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 860;
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('Coverage', color: AppColors.teal),
            const SizedBox(height: 16),
            Text(
              'What the answers are built on.',
              style: (narrow ? t.headlineMedium : t.displaySmall)?.copyWith(
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 20),
            _ChevronLink('Explore the court', () => context.go(Routes.courts)),
          ],
        );
        final table = Column(
          children: [
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        r.$1,
                        style: t.titleSmall?.copyWith(color: AppColors.navy),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: Text(
                        r.$2,
                        style: t.bodyMedium?.copyWith(color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        if (narrow) {
          return Column(children: [intro, const SizedBox(height: 32), table]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: intro),
            const SizedBox(width: 72),
            Expanded(flex: 7, child: table),
          ],
        );
      },
    );
  }
}
