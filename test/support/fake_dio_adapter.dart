import 'dart:typed_data';
import 'package:dio/dio.dart';

/// A minimal [HttpClientAdapter] fake for tests — the dio equivalent of
/// `package:http/testing`'s `MockClient`. Each request is handled by
/// [handler], which returns the status code and body to respond with.
class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.handler);

  final Future<({int statusCode, String body})> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = await handler(options);
    return ResponseBody.fromString(result.body, result.statusCode);
  }

  @override
  void close({bool force = false}) {}
}

/// A [Dio] instance wired to [FakeHttpClientAdapter], for injecting into
/// `GeminiApiService`/`GeminiTtsService` in tests.
Dio fakeDio(
  Future<({int statusCode, String body})> Function(RequestOptions options) handler,
) {
  return Dio()..httpClientAdapter = FakeHttpClientAdapter(handler);
}
