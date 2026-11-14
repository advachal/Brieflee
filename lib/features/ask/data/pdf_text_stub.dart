import 'dart:typed_data';

/// PDF reading is implemented for the web build. On Android and iOS the
/// knowledge service (server/) will take uploads instead.
Future<String> extractPdfText(Uint8List bytes) async => throw UnsupportedError(
  'Reading PDFs on this device is not supported yet. Paste the text instead.',
);
