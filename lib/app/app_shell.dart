import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/auth_controller.dart';
import '../core/widgets/common.dart';
import '../features/notifications/application/alert_providers.dart';
import '../shared/constants/breakpoints.dart';
import 'theme/app_colors.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _railDests = [
  _Dest('/', 'Home', Icons.home_outlined, Icons.home),
  _Dest('/ask', 'Ask', Icons.search_outlined, Icons.search),
  _Dest('/matters/new', 'New matter', Icons.note_add_outlined, Icons.note_add),
  _Dest(
    '/courts',
    'Courts',
    Icons.account_balance_outlined,
    Icons.account_balance,
  ),
  _Dest('/judges', 'Judges', Icons.gavel_outlined, Icons.gavel),
  _Dest('/saved', 'Saved', Icons.bookmark_border, Icons.bookmark),
  _Dest('/alerts', 'Alerts', Icons.notifications_none, Icons.notifications),
  _Dest('/settings', 'Settings', Icons.tune_outlined, Icons.tune),
  _Dest(
    '/admin',
    'Admin',
    Icons.admin_panel_settings_outlined,
    Icons.admin_panel_settings,
  ),
];

const _bottomDests = [
  _Dest('/', 'Home', Icons.home_outlined, Icons.home),
  _Dest('/ask', 'Ask', Icons.search_outlined, Icons.search),
  _Dest(
    '/courts',
    'Courts',
    Icons.account_balance_outlined,
    Icons.account_balance,
  ),
  _Dest('/saved', 'Saved', Icons.bookmark_border, Icons.bookmark),
];

int _indexFor(String location, List<_Dest> dests) {
  var best = -1;
  var bestLen = -1;
  for (var i = 0; i < dests.length; i++) {
    final p = dests[i].path;
    final match = p == '/' ? location == '/' : location.startsWith(p);
    if (match && p.length > bestLen) {
      best = i;
      bestLen = p.length;
    }
  }
  return best;
}

/// Responsive navigation: a navy rail on tablets and desktop, a bottom bar
/// with a "More" sheet on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final unread = ref.watch(unreadAlertCountProvider);
    final user = ref.watch(authControllerProvider);

    Widget icon(_Dest d, bool selected) {
      final i = Icon(selected ? d.selectedIcon : d.icon);
      if (d.path == '/alerts' && unread > 0) {
        return Badge(label: Text('$unread'), child: i);
      }
      return i;
    }

    if (compact) {
      final idx = _indexFor(location, _bottomDests);
      return Scaffold(
        appBar: AppBar(
          title: const _Brand(dark: false),
          actions: [_AccountButton(user: user)],
        ),
        body: Column(
          children: [
            DataNoticeBanner(location: location),
            Expanded(child: child),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx < 0 ? _bottomDests.length : idx,
          onDestinationSelected: (i) {
            if (i == _bottomDests.length) {
              _showMore(context);
            } else {
              context.go(_bottomDests[i].path);
            }
          },
          destinations: [
            for (final d in _bottomDests)
              NavigationDestination(
                icon: icon(d, false),
                selectedIcon: icon(d, true),
                label: d.label,
              ),
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      );
    }

    // Tablet and desktop: a quiet, editorial top bar (white, hairline rule,
    // text links) instead of a heavy side rail.
    final idx = _indexFor(location, _railDests);
    final width = MediaQuery.sizeOf(context).width;
    final showLabels = width >= 1180;
    const primary = [
      0,
      1,
      3,
      4,
      5,
      6,
    ]; // Home, Ask, Courts, Judges, Saved, Alerts
    return Scaffold(
      body: Column(
        children: [
          Material(
            color: AppColors.surface,
            child: Container(
              height: 68,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    child: const _Brand(dark: false),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final i in primary)
                            _TopLink(
                              dest: _railDests[i],
                              selected: idx == i,
                              showLabel: showLabels,
                              icon: icon(_railDests[i], idx == i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_horiz, color: AppColors.navy),
                    onSelected: (p) => context.go(p),
                    itemBuilder: (_) => [
                      for (final d in [_railDests[6], _railDests[7]])
                        PopupMenuItem(value: d.path, child: Text(d.label)),
                      const PopupMenuItem(
                        value: '/compare',
                        child: Text('Compare advocates'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => context.go('/matters/new'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('New matter'),
                  ),
                  const SizedBox(width: 8),
                  _AccountButton(user: user),
                ],
              ),
            ),
          ),
          DataNoticeBanner(location: location),
          Expanded(child: child),
        ],
      ),
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in const [
              _Dest(
                '/alerts',
                'Alerts',
                Icons.notifications_none,
                Icons.notifications,
              ),
              _Dest(
                '/matters/new',
                'New matter',
                Icons.note_add_outlined,
                Icons.note_add,
              ),
              _Dest(
                '/judges',
                'Judge explorer',
                Icons.gavel_outlined,
                Icons.gavel,
              ),
              _Dest(
                '/compare',
                'Compare advocates',
                Icons.compare_arrows,
                Icons.compare_arrows,
              ),
              _Dest(
                '/settings',
                'Settings & privacy',
                Icons.tune_outlined,
                Icons.tune,
              ),
              _Dest(
                '/admin',
                'Admin dashboard',
                Icons.admin_panel_settings_outlined,
                Icons.admin_panel_settings,
              ),
            ])
              ListTile(
                leading: Icon(d.icon, color: AppColors.navy),
                title: Text(d.label),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.go(d.path);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: dark ? AppColors.gold : AppColors.navy,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.balance,
        size: 20,
        color: dark ? AppColors.navy : AppColors.gold,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Brief',
                  style: TextStyle(color: dark ? Colors.white : AppColors.navy),
                ),
                TextSpan(
                  text: 'lee',
                  style: TextStyle(
                    color: dark ? AppColors.gold : AppColors.teal,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
      ],
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.user});
  final AppUser? user;
  bool get onDark => false;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return TextButton(
        onPressed: () => context.go('/login'),
        style: TextButton.styleFrom(
          foregroundColor: onDark ? Colors.white : AppColors.navy,
        ),
        child: const Text('Sign in'),
      );
    }
    return Tooltip(
      message: '${user!.name} · ${user!.role.label}',
      child: InkWell(
        onTap: () => context.go('/login'),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: onDark ? AppColors.gold : AppColors.navy,
            child: Text(
              user!.name.isEmpty ? '?' : user!.name[0].toUpperCase(),
              style: TextStyle(
                color: onDark ? AppColors.navy : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopLink extends StatelessWidget {
  const _TopLink({
    required this.dest,
    required this.selected,
    required this.showLabel,
    required this.icon,
  });

  final _Dest dest;
  final bool selected;
  final bool showLabel;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.navy : AppColors.muted;
    final child = showLabel
        ? Text(
            dest.label,
            style: TextStyle(
              fontSize: 16,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          )
        : IconTheme(
            data: IconThemeData(color: color, size: 22),
            child: icon,
          );
    return Tooltip(
      message: dest.label,
      child: InkWell(
        onTap: () => context.go(dest.path),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.gold : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
