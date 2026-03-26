import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:smartgo/data/datasources/payment_remote_data_source.dart';
import 'package:smartgo/data/models/payment_response_models.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:url_launcher/url_launcher.dart';

class RoutePaymentResultScreen extends StatefulWidget {
  static const String providerVnpay = 'VNPAY';
  static const String providerMomo = 'MoMo';

  final BusRoute route;
  final String ticketLabel;
  final int quantity;
  final String selectedBank;
  final int totalAmount;
  final VnpayCreatePaymentResponse createResponse;
  final String accessToken;
  final String paymentProvider;

  const RoutePaymentResultScreen({
    super.key,
    required this.route,
    required this.ticketLabel,
    required this.quantity,
    required this.selectedBank,
    required this.totalAmount,
    required this.createResponse,
    required this.accessToken,
    required this.paymentProvider,
  });

  @override
  State<RoutePaymentResultScreen> createState() =>
      _RoutePaymentResultScreenState();
}

class _RoutePaymentResultScreenState extends State<RoutePaymentResultScreen> {
  final http.Client _client = http.Client();
  late final PaymentRemoteDataSource _paymentRemoteDataSource;
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  bool _isLoading = false;
  bool _hasCheckedStatus = false;
  VnpayReturnResponse? _returnResponse;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _paymentRemoteDataSource = PaymentRemoteDataSourceImpl(client: _client);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _fetchPaymentStatus() async {
    setState(() {
      _isLoading = true;
      _hasCheckedStatus = true;
      _errorMessage = null;
    });

    try {
      final returnResult =
          widget.paymentProvider == RoutePaymentResultScreen.providerMomo
              ? await _paymentRemoteDataSource.getMomoReturnResult(
                  widget.accessToken,
                )
              : await _paymentRemoteDataSource.getVnpayReturnResult(
                  widget.accessToken,
                );

      if (!mounted) return;
      setState(() {
        _returnResponse = returnResult;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Chưa nhận được kết quả thanh toán. Vui lòng thử lại sau ít giây.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: AppBar(
        title: const Text('Kết quả thanh toán'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBodyByState(scheme),
    );
  }

  Widget _buildBodyByState(ColorScheme scheme) {
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (!_hasCheckedStatus || _returnResponse == null) {
      return _buildPendingState(scheme);
    }

    return _buildResultContent(scheme);
  }

  Widget _buildPendingState(ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.open_in_new, size: 64, color: Colors.orange),
                const SizedBox(height: 12),
                const Text(
                  'Đang chờ hoàn tất thanh toán',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Cổng: ${widget.paymentProvider}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mã giao dịch: ${widget.createResponse.txnRef}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailCard(
            context,
            title: 'Hướng dẫn',
            rows: [
              _StaticDetailRow(
                '1. Hoàn tất thanh toán trên trang ${widget.paymentProvider}.',
              ),
              const _StaticDetailRow('2. Quay lại app SmartGo.'),
              const _StaticDetailRow(
                '3. Bấm "Kiểm tra kết quả" để lấy trạng thái.',
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _fetchPaymentStatus,
              child: const Text('Kiểm tra kết quả'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openPaymentPageAgain,
              child: Text('Mở lại trang thanh toán ${widget.paymentProvider}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Quay lại'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pending_actions_outlined,
                size: 72, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Đã xảy ra lỗi.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Mã giao dịch: ${widget.createResponse.txnRef}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _fetchPaymentStatus,
                child: const Text('Kiểm tra lại kết quả'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Quay lại'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent(ColorScheme scheme) {
    final returnResponse = _returnResponse!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: returnResponse.success
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: returnResponse.success
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  returnResponse.success ? Icons.check_circle : Icons.error,
                  color: returnResponse.success ? Colors.green : Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text(
                  returnResponse.success
                      ? 'Thanh toán thành công'
                      : 'Thanh toán chưa thành công',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tuyến ${widget.route.routeCode} - ${widget.ticketLabel} x${widget.quantity}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailCard(
            context,
            title: 'Chi tiết giao dịch',
            rows: [
              _detailRow('Mã giao dịch', returnResponse.txnRef),
              _detailRow(
                  'Mã ${widget.paymentProvider}', returnResponse.transactionNo),
              _detailRow('Số tiền', _formatVnd(widget.totalAmount)),
              _detailRow('Mô tả', returnResponse.orderInfo),
              _detailRow('Ngân hàng', widget.selectedBank),
              _detailRow('Thời gian', returnResponse.payDate),
              _detailRow('Mã phản hồi', returnResponse.responseCode),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _fetchPaymentStatus,
              child: const Text('Cập nhật trạng thái'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openPaymentPageAgain,
              child: Text('Mở lại trang thanh toán ${widget.paymentProvider}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Quay lại màn thanh toán'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentPageAgain() async {
    // Allows user to continue payment flow if they returned before completion.
    final paymentUri = Uri.tryParse(widget.createResponse.paymentUrl);
    if (paymentUri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Liên kết thanh toán không hợp lệ.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final opened = await launchUrl(
      paymentUri,
      mode: LaunchMode.externalApplication,
    );

    if (!mounted || opened) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Không thể mở trang thanh toán ${widget.paymentProvider}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatVnd(int amount) {
    return '${_currencyFormat.format(amount)}đ';
  }
}

class _StaticDetailRow extends StatelessWidget {
  final String text;

  const _StaticDetailRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
