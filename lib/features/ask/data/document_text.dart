import 'dart:convert';
import 'dart:typed_data';

import 'pdf_text_stub.dart' if (dart.library.js_interop) 'pdf_text_web.dart';

/// Extracts plain text from an uploaded judgment, pleading or note.
///
/// PDFs are read in the browser with pdf.js; nothing is uploaded anywhere.
/// Scanned PDFs without a text layer return little or no text.
Future<String> extractDocumentText(String fileName, Uint8List bytes) async {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return extractPdfText(bytes);
  return utf8.decode(bytes, allowMalformed: true);
}

/// File types the upload box accepts.
const uploadExtensions = ['pdf', 'txt', 'md'];
