import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Advocates chosen for side-by-side comparison (max three).
class ComparisonSelection extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void setAll(List<String> ids) => state = ids.take(3).toList();

  void toggle(String id) {
    if (state.contains(id)) {
      state = state.where((x) => x != id).toList();
    } else if (state.length < 3) {
      state = [...state, id];
    }
  }
}

final comparisonSelectionProvider =
    NotifierProvider<ComparisonSelection, List<String>>(
      ComparisonSelection.new,
    );
