import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../config/app_config.dart';

/// Picks the right notice for the page: real public records on Ask and
/// Records pages, the demo-data notice everywhere else.
class DataNoticeBanner extends StatelessWidget {
  const DataNoticeBanner({super.key, required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Real records notice',
      child: Container(
        width: double.infinity,
        color: AppColors.tealSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: const Row(
          children: [
            Icon(Icons.verified_outlined, size: 16, color: AppColors.teal),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                AppConfig.publicRecordsNotice,
                style: TextStyle(fontSize: 12, color: Color(0xFF0B4F4E)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gold strip shown on every page while the app runs on demo data.
class DemoDataBanner extends StatelessWidget {
  const DemoDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.dataMode != DataMode.demo) return const SizedBox.shrink();
    return Semantics(
      label: 'Demo data notice',
      child: Container(
        width: double.infinity,
        color: AppColors.goldSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: const Row(
          children: [
            Icon(Icons.science_outlined, size: 16, color: Color(0xFF8A6A1F)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                AppConfig.demoDisclaimer,
                style: TextStyle(fontSize: 12, color: Color(0xFF5E4710)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: MediaQuery.sizeOf(context).width < 600
                          ? t.headlineSmall
                          : t.headlineLarge,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: t.bodyLarge?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: t.titleMedium),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: t.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 18),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.tealSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: AppColors.teal),
              ),
              const SizedBox(height: 16),
              Text(title, style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Something went wrong',
    message: error.toString(),
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
  );
}

/// Renders an [AsyncValue] with consistent loading and error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingLabel = 'Loading…',
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => LoadingView(label: loadingLabel),
    error: (e, _) => ErrorView(error: e, onRetry: onRetry),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.onTap,
    this.color = AppColors.navy,
  });

  final String label;
  final String value;
  final String? hint;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    value,
                    style: t.titleLarge?.copyWith(color: color, height: 1.1),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: t.bodySmall?.copyWith(color: AppColors.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: t.labelSmall?.copyWith(color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.child});
  final String label;
  final String value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 380;
          final labelW = Text(
            label,
            style: t.bodySmall?.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          );
          final valueW = child ?? SelectableText(value, style: t.bodyMedium);
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelW, const SizedBox(height: 2), valueW],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: labelW),
              Expanded(child: valueW),
            ],
          );
        },
      ),
    );
  }
}

/// Horizontal bar for a normalised score component.
class ComponentBar extends StatelessWidget {
  const ComponentBar({
    super.key,
    required this.label,
    required this.value,
    required this.weight,
    this.applied = true,
  });

  final String label;
  final double value;
  final double weight;
  final bool applied;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: t.bodySmall)),
              Text(
                applied
                    ? '${(value * 100).round()} · weight ${(weight * 100).round()}%'
                    : 'not applied',
                style: t.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: applied ? value.clamp(0, 1) : 0,
              minHeight: 6,
              backgroundColor: AppColors.border,
              color: AppColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 1100});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

/// Standard scrollable page body with consistent padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1100});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 600 ? 16.0 : (w < 1100 ? 32.0 : 48.0);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, w < 600 ? 20 : 44, pad, 64),
      children: [
        MaxWidth(
          width: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
