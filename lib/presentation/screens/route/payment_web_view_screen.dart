import 'package:flutter/material.dart';
import 'package:smartgo/core/utils/open_external_url.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final Uri initialUrl;
  final String provider;

  const PaymentWebViewScreen({
    super.key,
    required this.initialUrl,
    required this.provider,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.navigate;
            }

            // Intercept app deep links and hand them to the OS so SmartGo opens.
            if (uri.scheme == 'smartgo') {
              _openDeepLinkAndClose(uri);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(widget.initialUrl);
  }

  Future<void> _openDeepLinkAndClose(Uri deepLink) async {
    await openExternalUrl(deepLink);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Thanh toán ${widget.provider.toUpperCase()}'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
