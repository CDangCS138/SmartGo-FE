import 'package:web/web.dart' as web;

Future<bool> openExternalUrl(
  Uri uri, {
  String webTarget = '_self',
}) async {
  final url = uri.toString();

  if (webTarget == '_self') {
    web.window.location.href = url;
    return true;
  }

  web.window.open(url, webTarget);
  return true;
}
