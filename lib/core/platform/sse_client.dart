import 'sse_client_base.dart';
import 'sse_client_stub.dart' if (dart.library.html) 'sse_client_web.dart'
    as impl;

export 'sse_client_base.dart';

SseClient createSseClient() => impl.createSseClient();
