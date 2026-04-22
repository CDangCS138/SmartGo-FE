import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client createInnerHttpClient() {
  final client = BrowserClient()..withCredentials = true;
  return client;
}
