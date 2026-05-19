import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smartgo/core/utils/open_external_url.dart';
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
    final isSuccess = returnResponse.success;
    final amount = _resolveGatewayAmount(returnResponse);
    final ticketCode = _resolveTicketCode(returnResponse);
    final bankLabel = _resolveBankLabel(returnResponse);
    final payTimeText = _formatPayDate(returnResponse.payDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isSuccess
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSuccess
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? Colors.green : Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text(
                  isSuccess
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
          if (isSuccess) ...[
            _buildTicketReceiptCard(
              returnResponse: returnResponse,
              amount: amount,
              ticketCode: ticketCode,
              payTimeText: payTimeText,
              bankLabel: bankLabel,
            ),
            const SizedBox(height: 16),
          ],
          _buildDetailCard(
            context,
            title: 'Chi tiết giao dịch',
            rows: [
              if (ticketCode != null) _detailRow('Mã vé', ticketCode),
              _detailRow('Mã giao dịch', returnResponse.txnRef),
              _detailRow(
                'Mã ${widget.paymentProvider}',
                returnResponse.transactionNo,
              ),
              _detailRow('Số tiền', _formatVnd(amount)),
              if (returnResponse.orderInfo.isNotEmpty)
                _detailRow('Mô tả', returnResponse.orderInfo),
              _detailRow('Kênh thanh toán', bankLabel),
              _detailRow('Thời gian', payTimeText),
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

  Widget _buildTicketReceiptCard({
    required VnpayReturnResponse returnResponse,
    required int amount,
    required String? ticketCode,
    required String payTimeText,
    required String bankLabel,
  }) {
    final unitAmount = widget.quantity > 0 ? amount ~/ widget.quantity : amount;
    final routeTitle = 'Tuyến ${widget.route.routeCode}';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const Text(
                  'SMARTGO PAY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'VÉ ${widget.ticketLabel.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$routeTitle • ${widget.route.routeName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDottedDivider(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQrBox(ticketCode),
                const SizedBox(height: 10),
                if (ticketCode != null)
                  Column(
                    children: [
                      const Text(
                        'Mã vé điện tử',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        ticketCode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                _buildTicketInfoRow('Số serial', returnResponse.txnRef),
                _buildTicketInfoRow(
                  'Mã giao dịch cổng',
                  returnResponse.transactionNo,
                ),
                _buildTicketInfoRow('Kênh thanh toán', bankLabel),
                _buildTicketInfoRow('Thời gian', payTimeText),
                _buildTicketInfoRow('Số lượng', '${widget.quantity} vé'),
                _buildTicketInfoRow('Giá vé', _formatVnd(unitAmount)),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF99F6E4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: Color(0xFF0F766E), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Tổng tiền',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatVnd(amount),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Giữ vé để xuất trình khi kiểm soát lên xe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrBox(String? ticketCode) {
    if (ticketCode == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 56, color: Color(0xFFCBD5E1)),
            SizedBox(height: 8),
            Text(
              'Chưa có mã vé',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      alignment: Alignment.center,
      child: QrImageView(
        data: ticketCode,
        version: QrVersions.auto,
        size: 220,
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _buildTicketInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDottedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 6.0;
        final dashCount = (constraints.maxWidth / (dashWidth * 1.8)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: 6,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFE2E8F0)),
              ),
            );
          }),
        );
      },
    );
  }

  int _resolveGatewayAmount(VnpayReturnResponse response) {
    final amount = response.amount;
    if (amount <= 0) {
      return widget.totalAmount;
    }

    final isVnpay =
        widget.paymentProvider == RoutePaymentResultScreen.providerVnpay;
    if (isVnpay && widget.totalAmount > 0) {
      final scaled = amount ~/ 100;
      if (amount >= widget.totalAmount * 100 && amount % 100 == 0) {
        return scaled;
      }
    }

    return amount;
  }

  String _resolveBankLabel(VnpayReturnResponse response) {
    if (response.bankCode.isNotEmpty) {
      return response.bankCode;
    }
    return widget.selectedBank;
  }

  String _formatPayDate(String raw) {
    if (raw.isEmpty) {
      return '-';
    }

    try {
      if (raw.length == 14) {
        final parsed = DateFormat('yyyyMMddHHmmss').parse(raw, true).toLocal();
        return DateFormat('HH:mm dd/MM/yyyy').format(parsed);
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return DateFormat('HH:mm dd/MM/yyyy').format(parsed.toLocal());
      }
    } catch (_) {
      return raw;
    }

    return raw;
  }

  String? _resolveTicketCode(VnpayReturnResponse response) {
    return _firstNonEmpty([
      response.qrData,
      response.transactionNo,
      response.txnRef,
    ]);
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

    bool opened;
    if (kIsWeb) {
      // Reopen in the same tab so provider callback can continue current flow.
      opened = await openExternalUrl(paymentUri, webTarget: '_self');

      if (!mounted || opened) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Không thể mở trang thanh toán ${widget.paymentProvider}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      opened = await launchUrl(
        paymentUri,
        mode: LaunchMode.externalApplication,
      );
    } on MissingPluginException {
      opened = await launchUrl(
        paymentUri,
        mode: LaunchMode.platformDefault,
      );
    }

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
