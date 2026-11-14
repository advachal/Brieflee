import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user has saved, kept on this device only.
class SavedState {
  const SavedState({this.counsel = const {}, this.searches = const []});

  /// Counsel id to name (the name is kept so the list renders instantly).
  final Map<int, String> counsel;

  /// Saved Ask questions, newest first.
  final List<String> searches;

  SavedState copyWith({Map<int, String>? counsel, List<String>? searches}) =>
      SavedState(
        counsel: counsel ?? this.counsel,
        searches: searches ?? this.searches,
      );

  Map<String, dynamic> toJson() => {
    'counsel': {for (final e in counsel.entries) '${e.key}': e.value},
    'searches': searches,
  };

  static SavedState fromJson(Map<String, dynamic> j) => SavedState(
    counsel: {
      for (final e in ((j['counsel'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): e.value as String,
    },
    searches: [...((j['searches'] as List?) ?? const []).cast<String>()],
  );
}

class SavedStore extends Notifier<SavedState> {
  static const _key = 'brieflee.saved.v1';

  @override
  SavedState build() {
    _load();
    return const SavedState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        state = SavedState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Storage unavailable (private window, tests): keep in memory only.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  bool isCounselSaved(int id) => state.counsel.containsKey(id);

  void toggleCounsel(int id, String name) {
    final m = {...state.counsel};
    m.containsKey(id) ? m.remove(id) : m[id] = name;
    state = state.copyWith(counsel: m);
    _persist();
  }

  bool isSearchSaved(String q) => state.searches.contains(q.trim());

  void toggleSearch(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    final list = [...state.searches];
    list.contains(s) ? list.remove(s) : list.insert(0, s);
    state = state.copyWith(searches: list);
    _persist();
  }
}

final savedProvider = NotifierProvider<SavedStore, SavedState>(SavedStore.new);
