/// A failure the UI can explain in plain language.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure(String what) : super('$what could not be found.');
}

class SourceUnavailableFailure extends AppFailure {
  const SourceUnavailableFailure(String source)
    : super(
        '$source is not connected yet. Access and permissions are '
        'still being confirmed.',
      );
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'The service could not be reached.']);
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure() : super('Please sign in to continue.');
}
