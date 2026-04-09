import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(
  Uri uri, {
  String webTarget = '_self',
}) async {
  return launchUrl(uri, mode: LaunchMode.platformDefault);
}
