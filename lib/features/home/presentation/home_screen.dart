import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/constants/breakpoints.dart';

/// Landing page. Editorial layout: a large centred statement, one search
/// field, then full-width sections separated by whitespace and hairlines.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _start() {
    final q = _query.text.trim();
    context.go(Routes.ask(q.isEmpty ? null : q));
  }

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
          child: _Hero(controller: _query, onSubmit: _start, compact: compact),
        ),
        _Section(
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
  const _Hero({
    required this.controller,
    required this.onSubmit,
    required this.compact,
  });
  final TextEditingController controller;
  final VoidCallback onSubmit;
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
            'Ask in plain English, or upload a judgment. We search 109,000 real Delhi High Court '
            'decisions, read the outcomes, and show which counsel won similar '
            'matters, with every judgment linked.',
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
          child: Container(
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
                    controller: controller,
                    onSubmitted: (_) => onSubmit(),
                    style: const TextStyle(fontSize: 17),
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. Challenging an arbitral award under section 34',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: onSubmit,
                  child: Text(compact ? 'Ask' : 'Ask'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 28,
          runSpacing: 8,
          children: [
            _ChevronLink(
              'Describe a matter in detail',
              () => context.go(Routes.newMatter),
            ),
            _ChevronLink(
              'Upload a document',
              () => context.go('${Routes.newMatter}?mode=upload'),
            ),
            _ChevronLink(
              'Enter a case number',
              () => context.go('${Routes.newMatter}?mode=caseNumber'),
            ),
            _ChevronLink(
              'See the demo ranking',
              () => context.go(Routes.results('rec-demo-1')),
            ),
          ],
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
      'Tell us about the matter',
      'Plain language, a document or a case number. You review and edit everything we extract.',
    ),
    (
      'We check the court and bench',
      'Official rosters and cause lists, always shown with their source and freshness.',
    ),
    (
      'We find comparable judgments',
      'Vakilaj first, Indian Kanoon as fallback, official records to verify. Duplicates count once.',
    ),
    (
      'You see ranked, explained counsel',
      'Every number opens the cases behind it. Where evidence is thin, we say so.',
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
      ('Real-data court', 'Delhi High Court'),
      (
        'Initial categories',
        'Intellectual property, commercial disputes, interim injunctions',
      ),
      (
        'Vakilaj (primary source)',
        'Not connected: access and permissions pending',
      ),
      ('Indian Kanoon (secondary source)', 'Not connected: permission pending'),
      ('Official court records', 'Not connected in this prototype'),
      ('Data you will see', 'Fictional and illustrative only'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 860;
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('Prototype status', color: AppColors.teal),
            const SizedBox(height: 16),
            Text(
              'Built in the open about what is live and what is not.',
              style: (narrow ? t.headlineMedium : t.displaySmall)?.copyWith(
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 20),
            _ChevronLink(
              'Explore supported courts',
              () => context.go(Routes.courts),
            ),
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
