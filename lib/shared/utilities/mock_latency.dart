/// Simulated network latency for mock repositories, so loading states are
/// visible in the prototype. Set to zero in tests.
class MockLatency {
  static Duration base = const Duration(milliseconds: 350);

  static Future<void> wait([double factor = 1]) => base == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(base * factor);
}
