import '../../../core/public_records/public_records.dart';

/// Source of real public court records and their knowledge layer.
///
/// The pilot bundles a Delhi High Court snapshot in the app
/// ([BundledPublicRecordsRepository]). A deployment can swap in a
/// repository backed by the knowledge service in server/.
abstract interface class PublicRecordsRepository {
  Future<PublicRecordsSnapshot> load();
}
