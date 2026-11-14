import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/auth_controller.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/advocate_comparison/presentation/advocate_comparison_screen.dart';
import '../features/advocate_profile/presentation/advocate_profile_screen.dart';
import '../features/advocate_search/presentation/search_results_screen.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/case_analysis/presentation/case_analysis_screen.dart';
import '../features/case_intake/presentation/new_matter_screen.dart';
import '../features/court_explorer/presentation/court_detail_screen.dart';
import '../features/court_explorer/presentation/court_explorer_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/judge_roster/presentation/judge_explorer_screen.dart';
import '../features/judgment_viewer/presentation/judgment_details_screen.dart';
import '../features/notifications/presentation/alerts_screen.dart';
import '../features/saved_matters/presentation/saved_matters_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/ask/presentation/ask_screen.dart';
import '../features/ask/presentation/record_screens.dart';
import 'app_shell.dart';

abstract final class Routes {
  static const home = '/';
  static String ask([String? q]) =>
      q == null ? '/ask' : '/ask?q=${Uri.encodeComponent(q)}';
  static String record(String id) => '/records/cases/$id';
  static String recordCounsel(int id) => '/records/counsel/$id';
  static String recordJudge(int id) => '/records/judges/$id';
  static const login = '/login';
  static const newMatter = '/matters/new';
  static String analysis(String matterId) => '/matters/$matterId/analysis';
  static String results(String recId) => '/recommendations/$recId';
  static const courts = '/courts';
  static String court(String id) => '/courts/$id';
  static String judges({String court = 'dhc', String? tab}) =>
      '/judges?court=$court${tab == null ? '' : '&tab=$tab'}';
  static String advocate(String id, {String? rec}) =>
      '/advocates/$id${rec == null ? '' : '?rec=$rec'}';
  static String compare({String? rec, List<String> ids = const []}) {
    final q = <String>[
      if (rec != null) 'rec=$rec',
      if (ids.isNotEmpty) 'ids=${ids.join(',')}',
    ];
    return '/compare${q.isEmpty ? '' : '?${q.join('&')}'}';
  }

  static String judgment(String id) => '/judgments/$id';
  static const saved = '/saved';
  static const alerts = '/alerts';
  static const settings = '/settings';
  static const admin = '/admin';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(authControllerProvider);
      if (state.matchedLocation.startsWith(Routes.admin) &&
          (user == null || !user.canAdminister)) {
        return '${Routes.login}?from=${Uri.encodeComponent(Routes.admin)}';
      }
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri.path}')),
    ),
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/ask',
            builder: (_, s) =>
                AskScreen(initialQuery: s.uri.queryParameters['q']),
          ),
          GoRoute(
            path: '/records/cases/:id',
            builder: (_, s) =>
                RecordCaseScreen(recordId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/records/counsel/:id',
            builder: (_, s) => RecordCounselScreen(
              counselId: int.parse(s.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/records/judges/:id',
            builder: (_, s) =>
                RecordJudgeScreen(judgeId: int.parse(s.pathParameters['id']!)),
          ),
          GoRoute(
            path: '/login',
            builder: (_, s) => LoginScreen(from: s.uri.queryParameters['from']),
          ),
          GoRoute(
            path: '/matters/new',
            builder: (_, s) => NewMatterScreen(
              initialMode: s.uri.queryParameters['mode'],
              initialText: s.uri.queryParameters['q'],
            ),
          ),
          GoRoute(
            path: '/matters/:id/analysis',
            builder: (_, s) =>
                CaseAnalysisScreen(matterId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/recommendations/:id',
            builder: (_, s) =>
                SearchResultsScreen(recommendationId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/courts',
            builder: (_, _) => const CourtExplorerScreen(),
          ),
          GoRoute(
            path: '/courts/:id',
            builder: (_, s) =>
                CourtDetailScreen(courtId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/judges',
            builder: (_, s) => JudgeExplorerScreen(
              courtId: s.uri.queryParameters['court'] ?? 'dhc',
              initialTab: s.uri.queryParameters['tab'],
            ),
          ),
          GoRoute(
            path: '/advocates/:id',
            builder: (_, s) => AdvocateProfileScreen(
              advocateId: s.pathParameters['id']!,
              recommendationId: s.uri.queryParameters['rec'],
            ),
          ),
          GoRoute(
            path: '/compare',
            builder: (_, s) => AdvocateComparisonScreen(
              recommendationId: s.uri.queryParameters['rec'],
              advocateIds: (s.uri.queryParameters['ids'] ?? '')
                  .split(',')
                  .where((e) => e.isNotEmpty)
                  .toList(),
            ),
          ),
          GoRoute(
            path: '/judgments/:id',
            builder: (_, s) =>
                JudgmentDetailsScreen(judgmentId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/saved',
            builder: (_, _) => const SavedMattersScreen(),
          ),
          GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: '/admin',
            builder: (_, _) => const AdminDashboardScreen(),
          ),
        ],
      ),
    ],
  );
});
