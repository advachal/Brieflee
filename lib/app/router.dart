import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/ask/presentation/ask_screen.dart';
import '../features/ask/presentation/record_screens.dart';
import '../features/directory/presentation/directory_screens.dart';
import 'app_shell.dart';

abstract final class Routes {
  static const home = '/';
  static String ask([String? q]) =>
      q == null ? '/ask' : '/ask?q=${Uri.encodeComponent(q)}';
  static const upload = '/ask?upload=1';
  static String record(String id) => '/records/cases/$id';
  static String recordCounsel(int id) => '/records/counsel/$id';
  static String recordJudge(int id) => '/records/judges/$id';
  static String counsel({String? subject, String? q}) {
    final p = <String>[
      if (subject != null) 'subject=$subject',
      if (q != null) 'q=${Uri.encodeComponent(q)}',
    ];
    return '/counsel${p.isEmpty ? '' : '?${p.join('&')}'}';
  }

  static const courts = '/courts';
  static String judges() => '/judges';
  static const saved = '/saved';
  static const settings = '/settings';
}

/// Pages from the first, demo-data prototype. They are no longer reachable:
/// everything now runs on the real records, so these paths open Ask.
const _retiredPaths = [
  '/matters',
  '/recommendations',
  '/advocates',
  '/compare',
  '/judgments',
  '/alerts',
  '/admin',
  '/login',
];

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    redirect: (context, state) {
      final path = state.uri.path;
      if (_retiredPaths.any((p) => path == p || path.startsWith('$p/'))) {
        return path.startsWith('/matters/new') &&
                state.uri.queryParameters['mode'] == 'upload'
            ? Routes.upload
            : Routes.ask(state.uri.queryParameters['q']);
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
            builder: (_, s) => AskScreen(
              initialQuery: s.uri.queryParameters['q'],
              openUpload: s.uri.queryParameters['upload'] == '1',
            ),
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
            path: '/counsel',
            builder: (_, s) => CounselDirectoryScreen(
              subject: s.uri.queryParameters['subject'],
              query: s.uri.queryParameters['q'],
            ),
          ),
          GoRoute(
            path: '/courts',
            builder: (_, _) => const CourtsOverviewScreen(),
          ),
          GoRoute(
            path: '/courts/:id',
            builder: (_, _) => const CourtsOverviewScreen(),
          ),
          GoRoute(
            path: '/judges',
            builder: (_, _) => const JudgesDirectoryScreen(),
          ),
          GoRoute(path: '/saved', builder: (_, _) => const SavedScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
