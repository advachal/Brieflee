import '../../../core/models/models.dart';

/// Client-side checks before a secure upload. The server repeats every check
/// and adds malware scanning, encryption at rest and retention rules.
abstract final class UploadPolicy {
  static const allowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'txt',
    'rtf',
    'jpg',
    'jpeg',
    'png',
  ];
  static const maxBytes = 25 * 1024 * 1024;
  static const maxFiles = 10;

  static String? validate(String fileName, int sizeBytes) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      return '$fileName: file type .$ext is not supported.';
    }
    if (sizeBytes > maxBytes) {
      return '$fileName is larger than 25 MB.';
    }
    if (sizeBytes == 0) return '$fileName is empty.';
    return null;
  }

  static DocumentKind guessKind(String fileName) {
    final n = fileName.toLowerCase();
    if (n.contains('petition') || n.contains('plaint')) {
      return DocumentKind.petition;
    }
    if (n.contains('judgment')) return DocumentKind.judgment;
    if (n.contains('order')) return DocumentKind.order;
    if (n.contains('notice')) return DocumentKind.notice;
    if (n.contains('submission') || n.contains('written')) {
      return DocumentKind.submission;
    }
    return DocumentKind.other;
  }
}

/// A file chosen on the device but not yet uploaded.
class PendingUpload {
  PendingUpload({
    required this.fileName,
    required this.sizeBytes,
    required this.kind,
  });
  final String fileName;
  final int sizeBytes;
  DocumentKind kind;
}
