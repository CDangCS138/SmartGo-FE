abstract class SseClient {
  Stream<String> connect(Uri uri);

  void close();
}
