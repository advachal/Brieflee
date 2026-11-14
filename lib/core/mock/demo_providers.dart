import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'demo_dataset.dart';

final demoDatasetProvider = Provider<DemoDataset>(
  (ref) => DemoDataset.instance,
);
