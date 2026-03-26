import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/data/datasources/payment_remote_data_source.dart';
import 'package:smartgo/data/models/payment_request_models.dart';
import 'package:smartgo/data/models/payment_response_models.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/presentation/screens/route/route_payment_result_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class RouteTicketPaymentScreen extends StatefulWidget {
  final BusRoute route;

  const RouteTicketPaymentScreen({
    super.key,
    required this.route,
  });

  @override
  State<RouteTicketPaymentScreen> createState() =>
      _RouteTicketPaymentScreenState();
}

class _RouteTicketPaymentScreenState extends State<RouteTicketPaymentScreen> {
  static const String _providerVnpay = 'VNPAY';
  static const String _providerMomo = 'MoMo';

  static const List<_TicketOption> _ticketOptions = [
    _TicketOption(label: 'Vé lượt', description: 'Vé một lượt đi', price: 7000),
    _TicketOption(
        label: 'Vé HSSV',
        description: 'Vé dành cho học sinh, sinh viên',
        price: 3000),
    _TicketOption(
        label: 'Vé tháng',
        description: 'Vé sử dụng không giới hạn trong 30 ngày',
        price: 200000),
    _TicketOption(
        label: 'Vé tập', description: 'Gói 25 lượt đi', price: 157500),
  ];

  static const List<String> _banks = [
    'NCB',
    'Vietcombank',
    'VietinBank',
    'BIDV',
    'Techcombank',
    'MB Bank',
  ];

  int _selectedTicketIndex = 0;
  int _quantity = 1;
  String _selectedBank = _banks.first;
  String _selectedProvider = _providerVnpay;
  bool _isSubmitting = false;

  final http.Client _client = http.Client();
  late final PaymentRemoteDataSource _paymentRemoteDataSource;
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  static const Map<String, String> _bankCodeMap = {
    'NCB': 'NCB',
    'Vietcombank': 'VCB',
    'VietinBank': 'ICB',
    'BIDV': 'BIDV',
    'Techcombank': 'TCB',
    'MB Bank': 'MB',
  };

  int get _totalAmount =>
      _ticketOptions[_selectedTicketIndex].price * _quantity;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: AppBar(
        title: const Text('Thanh toán vé xe buýt'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tuyến ${widget.route.routeCode}',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRouteHeaderCard(scheme),
            const SizedBox(height: 16),
            _buildSectionCard(
              scheme,
              title: 'Loại vé',
              icon: Icons.confirmation_num_outlined,
              child: Column(
                children: _ticketOptions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final selected = index == _selectedTicketIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedTicketIndex = index),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: selected ? 1.8 : 1,
                          ),
                          color: selected
                              ? scheme.primaryContainer.withValues(alpha: 0.4)
                              : scheme.surface,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.label,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    option.description,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatVnd(option.price),
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              scheme,
              title: 'Số lượng',
              icon: Icons.calculate_outlined,
              child: Row(
                children: [
                  _buildQuantityButton(
                      icon: Icons.remove, onTap: _decreaseQuantity),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: scheme.surfaceContainerHighest,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$_quantity',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildQuantityButton(
                      icon: Icons.add, onTap: _increaseQuantity),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              scheme,
              title: 'Cổng thanh toán',
              icon: Icons.payments_outlined,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [_providerVnpay, _providerMomo].map((provider) {
                  final selected = provider == _selectedProvider;
                  return ChoiceChip(
                    label: Text(provider),
                    selected: selected,
                    selectedColor: scheme.primary.withValues(alpha: 0.18),
                    onSelected: (_) =>
                        setState(() => _selectedProvider = provider),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              scheme,
              title: 'Ngân hàng thanh toán',
              icon: Icons.account_balance,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _banks.map((bank) {
                  final selected = bank == _selectedBank;
                  return ChoiceChip(
                    label: Text(bank),
                    selected: selected,
                    selectedColor: scheme.primary.withValues(alpha: 0.18),
                    onSelected: (_) => setState(() => _selectedBank = bank),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF255DE8), Color(0xFF8A1AF4)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tổng thanh toán',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatVnd(_totalAmount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF255DE8),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isSubmitting ? null : _onProceedPayment,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(
                        _isSubmitting
                            ? 'Đang xử lý thanh toán...'
                            : 'Thanh toán qua $_selectedProvider',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteHeaderCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF255DE8), Color(0xFF8A1AF4)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.route.routeCode} · ${widget.route.routeName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.route.startPoint} -> ${widget.route.endPoint}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                widget.route.tripTime,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 20),
              const Icon(Icons.straighten, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                '${widget.route.totalDistance.toStringAsFixed(1)} km',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    ColorScheme scheme, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildQuantityButton(
      {required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Icon(icon),
      ),
    );
  }

  void _decreaseQuantity() {
    if (_quantity <= 1) return;
    setState(() => _quantity -= 1);
  }

  void _increaseQuantity() {
    setState(() => _quantity += 1);
  }

  Future<void> _onProceedPayment() async {
    if (_isSubmitting) return;

    final accessToken = getIt<StorageService>().getAuthToken();
    if (accessToken == null || accessToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final selectedTicket = _ticketOptions[_selectedTicketIndex];
    final bankCode = _bankCodeMap[_selectedBank] ?? 'NCB';
    final isMomo = _selectedProvider == _providerMomo;

    late VnpayCreatePaymentResponse createResponse;

    try {
      final createRequest = VnpayCreatePaymentRequest(
        amount: _totalAmount,
        orderDescription:
            'Thanh toan ${selectedTicket.label} tuyen ${widget.route.routeCode} x$_quantity',
        orderType: 'other',
        bankCode: bankCode,
        locale: 'vn',
      );

      createResponse = isMomo
          ? await _paymentRemoteDataSource.createMomoPayment(
              createRequest,
              accessToken,
            )
          : await _paymentRemoteDataSource.createVnpayPayment(
              createRequest,
              accessToken,
            );

      final paymentUri = Uri.tryParse(createResponse.paymentUrl);
      if (paymentUri == null) {
        throw Exception('Liên kết thanh toán không hợp lệ');
      }

      await _openPaymentPage(paymentUri);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RoutePaymentResultScreen(
            route: widget.route,
            ticketLabel: selectedTicket.label,
            quantity: _quantity,
            selectedBank: _selectedBank,
            totalAmount: _totalAmount,
            createResponse: createResponse,
            accessToken: accessToken,
            paymentProvider: _selectedProvider,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xử lý thanh toán: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatVnd(int amount) {
    return '${_currencyFormat.format(amount)}đ';
  }

  Future<void> _openPaymentPage(Uri paymentUri) async {
    try {
      final opened = kIsWeb
          ? await launchUrl(paymentUri, webOnlyWindowName: '_self')
          : await launchUrl(
              paymentUri,
              mode: LaunchMode.externalApplication,
            );

      if (!opened) {
        throw Exception('Không thể mở trang thanh toán $_selectedProvider');
      }
    } on MissingPluginException {
      final opened = await launchUrl(
        paymentUri,
        mode: LaunchMode.platformDefault,
      );

      if (!opened) {
        throw Exception('Không thể mở trang thanh toán $_selectedProvider');
      }
    }
  }
}

class _TicketOption {
  final String label;
  final String description;
  final int price;

  const _TicketOption({
    required this.label,
    required this.description,
    required this.price,
  });
}
