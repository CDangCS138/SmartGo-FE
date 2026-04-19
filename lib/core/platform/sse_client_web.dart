// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'sse_client_base.dart';

class _WebSseClient implements SseClient {
  html.EventSource? _eventSource;
  void Function()? _closeController;

  @override
  Stream<String> connect(Uri uri) {
    return connectToEvents(uri).map((event) => event.data);
  }

  @override
  Stream<SseEvent> connectToEvents(
    Uri uri, {
    List<String> eventNames = const [],
  }) {
    close();

    final controller = StreamController<SseEvent>.broadcast(
      onCancel: close,
    );

    _closeController = () {
      if (!controller.isClosed) {
        controller.close();
      }
    };

    final source = html.EventSource(uri.toString());
    _eventSource = source;

    void emitEvent(String eventName, dynamic event) {
      if (controller.isClosed) {
        return;
      }

      String? payload;
      if (event is html.MessageEvent) {
        payload = event.data?.toString();
      } else {
        try {
          payload = (event as dynamic).data?.toString();
        } catch (_) {
          payload = null;
        }
      }

      if (payload == null || payload.isEmpty) {
        return;
      }

      controller.add(
        SseEvent(
          event: eventName,
          data: payload,
        ),
      );
    }

    source.onMessage.listen((event) {
      emitEvent('message', event);
    });

    final normalizedNames = eventNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name != 'message')
        .toSet();

    for (final eventName in normalizedNames) {
      source.addEventListener(
        eventName,
        (dynamic event) {
          emitEvent(eventName, event);
        },
      );
    }

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

    final closeController = _closeController;
    _closeController = null;
    closeController?.call();
  }
}

SseClient createSseClient() => _WebSseClient();
