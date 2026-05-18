import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/routes/app_routes.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/core/utils/open_external_url.dart';
import 'package:smartgo/data/datasources/payment_remote_data_source.dart';
import 'package:smartgo/data/models/payment_response_models.dart';

class PaymentCallbackScreen extends StatefulWidget {
  final String provider;
  final Map<String, String> callbackParams;

  const PaymentCallbackScreen({
    super.key,
    required this.provider,
    required this.callbackParams,
  });

  @override
  State<PaymentCallbackScreen> createState() => _PaymentCallbackScreenState();
}

class _PaymentCallbackScreenState extends State<PaymentCallbackScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  bool _isVerifying = true;
  VnpayReturnResponse? _verifyResponse;

  bool get _isMomo => widget.provider.toLowerCase() == 'momo';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInApp();
      });
    }

    _verifyWithBackend();
  }

  Future<void> _verifyWithBackend() async {
    setState(() {
      _isVerifying = true;
    });

    try {
      final accessToken = getIt<StorageService>().getAuthToken();
      final paymentDataSource = getIt<PaymentRemoteDataSource>();

      final result = _isMomo
          ? await paymentDataSource.getMomoReturnResult(
              accessToken,
              callbackParams: widget.callbackParams,
            )
          : await paymentDataSource.getVnpayReturnResult(
              accessToken,
              callbackParams: widget.callbackParams,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _verifyResponse = result;
        _isVerifying = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isVerifying = false;
      });
    }
  }

  bool _isCallbackSuccess() {
    if (_isMomo) {
      final resultCode = widget.callbackParams['resultCode'];
      return resultCode == '0';
    }

    final vnpCode = widget.callbackParams['vnp_ResponseCode'] ??
        widget.callbackParams['responseCode'];
    final successFlag = widget.callbackParams['success']?.toLowerCase().trim();
    if (successFlag == 'true') {
      return true;
    }
    return vnpCode == '00';
  }

  String _callbackCode() {
    if (_isMomo) {
      return widget.callbackParams['resultCode'] ?? '-';
    }

    return widget.callbackParams['vnp_ResponseCode'] ??
        widget.callbackParams['responseCode'] ??
        '-';
  }

  String _callbackAmountText() {
    if (_isMomo) {
      final raw = int.tryParse(widget.callbackParams['amount'] ?? '0') ?? 0;
      return raw > 0 ? '${_currencyFormat.format(raw)}đ' : '-';
    }

    final vnpAmount = widget.callbackParams['vnp_Amount'];
    final normalizedAmount = widget.callbackParams['amount'];
    final raw = int.tryParse(vnpAmount ?? normalizedAmount ?? '0') ?? 0;
    if (raw <= 0) {
      return '-';
    }

    final normalized = vnpAmount != null ? raw ~/ 100 : raw;
    return '${_currencyFormat.format(normalized)}đ';
  }

  String _callbackTxnRef() {
    if (_isMomo) {
      return widget.callbackParams['orderId'] ?? '-';
    }

    return widget.callbackParams['vnp_TxnRef'] ??
        widget.callbackParams['txnRef'] ??
        '-';
  }

  String _callbackTransactionNo() {
    if (_isMomo) {
      return widget.callbackParams['transId'] ?? '-';
    }

    return widget.callbackParams['vnp_TransactionNo'] ??
        widget.callbackParams['transactionNo'] ??
        '-';
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty && trimmed != '-') {
        return trimmed;
      }
    }
    return null;
  }

  String? _resolveQrData() {
    return _firstNonEmpty([
      _verifyResponse?.qrData,
      widget.callbackParams['qrData'],
      widget.callbackParams['qr_code'],
      widget.callbackParams['qrCode'],
      widget.callbackParams['ticketCode'],
      widget.callbackParams['ticket_code'],
      _callbackTxnRef(),
      _callbackTransactionNo(),
    ]);
  }

  Widget _buildQrSection({
    required bool effectiveSuccess,
    required String? qrData,
  }) {
    if (_isVerifying) {
      return const _SectionCard(
        title: 'Mã QR lên tàu',
        children: [
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 12),
          Text('Đang tạo mã QR...'),
        ],
      );
    }

    if (!effectiveSuccess) {
      return const _SectionCard(
        title: 'Mã QR lên tàu',
        children: [
          Text('Thanh toán chưa thành công. Chưa thể tạo mã QR.'),
        ],
      );
    }

    if (qrData == null) {
      return const _SectionCard(
        title: 'Mã QR lên tàu',
        children: [
          Text('Chưa có mã QR cho giao dịch này.'),
        ],
      );
    }

    return _SectionCard(
      title: 'Mã QR lên tàu',
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Dùng mã này để quét khi lên tàu.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Uri _buildAppDeepLink() {
    const providerPath = AppRoutes.paymentResult;
    return Uri(
      scheme: 'smartgo',
      host: 'payment',
      path: providerPath,
      queryParameters: widget.callbackParams.isEmpty
          ? null
          : Map<String, String>.from(widget.callbackParams),
    );
  }

  Future<void> _openInApp() async {
    final uri = _buildAppDeepLink();
    await openExternalUrl(uri, webTarget: '_self');
  }

  @override
  Widget build(BuildContext context) {
    final callbackSuccess = _isCallbackSuccess();
    final verifySuccess = _verifyResponse?.success;

    final effectiveSuccess = verifySuccess ?? callbackSuccess;

    final title = effectiveSuccess
        ? 'Thanh toán ${widget.provider.toUpperCase()} thành công'
        : 'Thanh toán ${widget.provider.toUpperCase()} chưa thành công';

    final subtitle = _isVerifying
        ? 'Đang xử lý kết quả thanh toán...'
        : (_verifyResponse != null
            ? 'Thanh toán đã được xác nhận.'
            : 'Đã nhận kết quả từ cổng thanh toán.');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mã QR lên tàu'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              success: effectiveSuccess,
              title: title,
              subtitle: subtitle,
            ),
            const SizedBox(height: 16),
            _buildQrSection(
              effectiveSuccess: effectiveSuccess,
              qrData: _resolveQrData(),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Tóm tắt callback',
              children: [
                _DetailRow(label: 'Provider', value: widget.provider),
                _DetailRow(label: 'Mã phản hồi', value: _callbackCode()),
                _DetailRow(label: 'Mã tham chiếu', value: _callbackTxnRef()),
                _DetailRow(
                  label: 'Mã giao dịch cổng',
                  value: _callbackTransactionNo(),
                ),
                _DetailRow(label: 'Số tiền', value: _callbackAmountText()),
              ],
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openInApp,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Mở trong ứng dụng SmartGo'),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.routes),
              child: const Text('Về danh sách tuyến'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Về trang chủ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool success;
  final String title;
  final String subtitle;

  const _StatusCard({
    required this.success,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(success ? Icons.check_circle : Icons.error, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
