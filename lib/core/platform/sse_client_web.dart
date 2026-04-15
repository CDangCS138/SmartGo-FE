// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'sse_client_base.dart';

class _WebSseClient implements SseClient {
  html.EventSource? _eventSource;
  StreamController<String>? _controller;

  @override
  Stream<String> connect(Uri uri) {
    close();

    final controller = StreamController<String>.broadcast(
      onCancel: close,
    );

    _controller = controller;
    final source = html.EventSource(uri.toString());
    _eventSource = source;

    source.onMessage.listen((event) {
      if (controller.isClosed) {
        return;
      }

      final payload = event.data?.toString();
      if (payload == null || payload.isEmpty) {
        return;
      }

      controller.add(payload);
    });

    source.onError.listen((_) {
      if (!controller.isClosed) {
        controller.addError(
          StateError('SSE connection error'),
        );
      }
    });

    return controller.stream;
  }

  @override
  void close() {
    _eventSource?.close();
    _eventSource = null;

    final controller = _controller;
    _controller = null;

    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }
}

SseClient createSseClient() => _WebSseClient();
