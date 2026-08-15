import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/guide_progress_estimator.dart';

void main() {
  test('averages default when no history recorded', () {
    final estimator = GuideProgressEstimator();
    expect(estimator.averageGpsDuration, 1.5);
    expect(estimator.averageAnalyzeDuration, 10.0);
  });

  test('averages reflect recorded durations', () {
    final estimator = GuideProgressEstimator();
    estimator.recordGpsDuration(1.0);
    estimator.recordGpsDuration(3.0);
    estimator.recordAnalyzeDuration(6.0);
    estimator.recordAnalyzeDuration(10.0);

    expect(estimator.averageGpsDuration, 2.0);
    expect(estimator.averageAnalyzeDuration, 8.0);
  });

  test('caps history at 5 samples, dropping the oldest', () {
    final estimator = GuideProgressEstimator();
    for (final d in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) {
      estimator.recordGpsDuration(d);
    }
    expect(estimator.gpsDurations, [2.0, 3.0, 4.0, 5.0, 6.0]);
  });

  test('estimateWhileLocating combines gps and analyze averages plus buffer', () {
    final estimator = GuideProgressEstimator(gpsDurations: [2.0], analyzeDurations: [8.0]);
    expect(estimator.estimateWhileLocating, 2.0 + 8.0 + 5.0);
  });

  test('estimateWhileAnalyzing shrinks as stepProgress advances', () {
    final estimator = GuideProgressEstimator(analyzeDurations: [10.0]);
    estimator.stepProgress = 0.5;
    expect(estimator.estimateWhileAnalyzing, 10.0 * 0.5 + 5.0);
  });

  test('stop sets stepProgress to 1.0', () {
    final estimator = GuideProgressEstimator();
    estimator.stepProgress = 0.3;
    estimator.stop();
    expect(estimator.stepProgress, 1.0);
  });
}
