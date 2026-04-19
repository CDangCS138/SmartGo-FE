class SseEvent {
  final String event;
  final String data;

  const SseEvent({
    required this.event,
    required this.data,
  });
}

abstract class SseClient {
  Stream<String> connect(Uri uri);

  Stream<SseEvent> connectToEvents(
    Uri uri, {
    List<String> eventNames = const [],
  });

  void close();
}
