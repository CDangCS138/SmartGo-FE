import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/routes/app_routes.dart';
import 'package:smartgo/core/services/storage_service.dart';
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
          ? await paymentDataSource.getMomoReturnResult(accessToken)
          : await paymentDataSource.getVnpayReturnResult(accessToken);

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

    final vnpCode = widget.callbackParams['vnp_ResponseCode'];
    return vnpCode == '00';
  }

  String _callbackCode() {
    if (_isMomo) {
      return widget.callbackParams['resultCode'] ?? '-';
    }

    return widget.callbackParams['vnp_ResponseCode'] ?? '-';
  }

  String _callbackAmountText() {
    if (_isMomo) {
      final raw = int.tryParse(widget.callbackParams['amount'] ?? '0') ?? 0;
      return raw > 0 ? '${_currencyFormat.format(raw)}đ' : '-';
    }

    final raw = int.tryParse(widget.callbackParams['vnp_Amount'] ?? '0') ?? 0;
    if (raw <= 0) {
      return '-';
    }

    final normalized = raw ~/ 100;
    return '${_currencyFormat.format(normalized)}đ';
  }

  String _callbackTxnRef() {
    if (_isMomo) {
      return widget.callbackParams['orderId'] ?? '-';
    }

    return widget.callbackParams['vnp_TxnRef'] ?? '-';
  }

  String _callbackTransactionNo() {
    if (_isMomo) {
      return widget.callbackParams['transId'] ?? '-';
    }

    return widget.callbackParams['vnp_TransactionNo'] ?? '-';
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
        title: const Text('Kết quả thanh toán'),
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
