import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/public_records/knowledge.dart';
import '../../../core/public_records/public_records.dart';
import '../domain/public_records_repository.dart';

/// Loads the snapshot shipped in assets/data (built by
/// tool/build_dhc_snapshot.py and tool/knowledge/build_knowledge.py).
class BundledPublicRecordsRepository implements PublicRecordsRepository {
  BundledPublicRecordsRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  static const _dir = 'assets/data';

  @override
  Future<PublicRecordsSnapshot> load() async {
    final manifest = jsonDecode(
      await _bundle.loadString('$_dir/courts.json'),
    ) as Map<String, dynamic>;
    final courts = (manifest['courts'] as List).cast<Map<String, dynamic>>();
    final loaded = await Future.wait([for (final c in courts) _loadCourt(c)]);
    return PublicRecordsSnapshot.merge(loaded);
  }

  Future<CourtSnapshotJson> _loadCourt(Map<String, dynamic> c) async {
    final index = jsonDecode(
      await _bundle.loadString('$_dir/${c['snapshot']}'),
    ) as Map<String, dynamic>;
    final parts = (index['meta']['parts'] as List).cast<String>();
    final texts = await Future.wait([
      for (final p in parts) _bundle.loadString('$_dir/$p', cache: false),
    ]);
    KnowledgeLayer? knowledge;
    final kName = c['knowledge'] as String?;
    if (kName != null) {
      try {
        final k = await _bundle.loadString('$_dir/$kName', cache: false);
        knowledge = KnowledgeLayer.fromJson(
          jsonDecode(k) as Map<String, dynamic>,
        );
      } on FlutterError {
        knowledge = null; // the knowledge layer is optional
      }
    }
    return CourtSnapshotJson(index, [
      for (final s in texts) jsonDecode(s) as List<dynamic>,
    ], knowledge);
  }
}
