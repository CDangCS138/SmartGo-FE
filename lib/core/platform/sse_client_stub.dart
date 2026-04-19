import 'dart:async';

import 'sse_client_base.dart';

class _StubSseClient implements SseClient {
  @override
  Stream<String> connect(Uri uri) {
    return Stream<String>.error(
      UnsupportedError('SSE is only available on Flutter web.'),
    );
  }

  @override
  Stream<SseEvent> connectToEvents(
    Uri uri, {
    List<String> eventNames = const [],
  }) {
    return Stream<SseEvent>.error(
      UnsupportedError('SSE is only available on Flutter web.'),
    );
  }

  @override
  void close() {}
}

SseClient createSseClient() => _StubSseClient();
