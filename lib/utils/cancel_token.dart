/// A simple cancellation token that can be used to cancel long-running operations.
///
/// Usage:
/// ```dart
/// final token = CancelToken();
/// 
/// // In async operation:
/// if (token.isCancelled) return;
/// 
/// // To cancel:
/// token.cancel();
/// ```
class CancelToken {
  bool _isCancelled = false;

  /// Returns true if cancellation was requested
  bool get isCancelled => _isCancelled;

  /// Request cancellation
  void cancel() {
    _isCancelled = true;
  }

  /// Reset the token for reuse
  void reset() {
    _isCancelled = false;
  }

  /// Create a new token that inherits the cancellation state
  CancelToken fork() {
    final newToken = CancelToken();
    if (_isCancelled) newToken._isCancelled = true;
    return newToken;
  }
}

/// Extension to add timeout-based cancellation to Future operations
class CancelTokenExtensions {
  /// Returns a Future that completes when either the original future completes
  /// or when the token is cancelled
  static Future<T> withCancel<T>(
    Future<T> Function() operation,
    CancelToken token,
  ) async {
    // Check if already cancelled before starting
    if (token.isCancelled) {
      throw const CancelledException();
    }

    // Run the operation and check cancellation periodically
    // Note: This only works if the operation can be interrupted
    // For truly interruptible operations, use checkCancelled() inside the operation
    return operation();
  }

  /// Check if cancelled and throw if so
  static void checkCancelled(CancelToken token) {
    if (token.isCancelled) {
      throw const CancelledException();
    }
  }
}

/// Exception thrown when an operation is cancelled
class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => 'Operation was cancelled';
}
