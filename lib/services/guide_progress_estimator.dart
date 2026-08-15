/// Tracks GPS/analysis step durations, simulates step progress, and
/// estimates remaining pipeline time (T06 — extracted from
/// AudioGuideService).
class GuideProgressEstimator {
  GuideProgressEstimator({List<double>? gpsDurations, List<double>? analyzeDurations})
      : gpsDurations = gpsDurations ?? [],
        analyzeDurations = analyzeDurations ?? [];

  static const _maxSamples = 5;
  static const _defaultAnalyzeSeconds = 10.0;
  static const _defaultGpsSeconds = 1.5;

  final List<double> gpsDurations;
  final List<double> analyzeDurations;

  /// Current step progress: 0.0-1.0, or -1.0 for an indeterminate step.
  double stepProgress = 0.0;

  bool _simulating = false;

  void recordGpsDuration(double seconds) => _record(gpsDurations, seconds);
  void recordAnalyzeDuration(double seconds) => _record(analyzeDurations, seconds);

  void _record(List<double> durations, double seconds) {
    durations.add(seconds);
    if (durations.length > _maxSamples) durations.removeAt(0);
  }

  double get averageGpsDuration => gpsDurations.isNotEmpty
      ? gpsDurations.reduce((a, b) => a + b) / gpsDurations.length
      : _defaultGpsSeconds;

  double get averageAnalyzeDuration => analyzeDurations.isNotEmpty
      ? analyzeDurations.reduce((a, b) => a + b) / analyzeDurations.length
      : _defaultAnalyzeSeconds;

  double get estimateWhileLocating => averageGpsDuration + averageAnalyzeDuration + 5.0;
  double get estimateWhileAnalyzing => averageAnalyzeDuration * (1 - stepProgress) + 5.0;

  /// Simulates progress towards [expectedDuration], calling [onTick] after
  /// each update, until it reaches 95% or [stop] is called. Not awaited by
  /// the caller — runs in the background while the real step proceeds.
  Future<void> simulate({
    required double expectedDuration,
    required void Function() onTick,
  }) async {
    _simulating = true;
    stepProgress = 0.0;
    final startTime = DateTime.now();
    while (_simulating && stepProgress < 0.95) {
      await Future.delayed(const Duration(milliseconds: 150));
      final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      stepProgress = 1.0 - (1.0 / (1.0 + elapsed / expectedDuration * 2));
      onTick();
    }
  }

  void stop() {
    _simulating = false;
    stepProgress = 1.0;
  }
}
