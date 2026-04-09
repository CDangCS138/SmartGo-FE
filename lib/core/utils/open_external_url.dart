import 'open_external_url_stub.dart'
    if (dart.library.html) 'open_external_url_web.dart' as impl;

Future<bool> openExternalUrl(
  Uri uri, {
  String webTarget = '_self',
}) {
  return impl.openExternalUrl(uri, webTarget: webTarget);
}
