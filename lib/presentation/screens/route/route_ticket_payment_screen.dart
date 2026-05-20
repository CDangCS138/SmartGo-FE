import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/errors/exceptions.dart';
import 'package:smartgo/core/constants/app_constants.dart';
import 'package:smartgo/core/constants/app_env.dart';
import 'package:smartgo/core/routes/app_routes.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/core/utils/open_external_url.dart';
import 'package:smartgo/data/datasources/bills_remote_data_source.dart';
import 'package:smartgo/data/datasources/payment_remote_data_source.dart';
import 'package:smartgo/data/models/bill_models.dart';
import 'package:smartgo/data/models/payment_request_models.dart';
import 'package:smartgo/data/models/payment_response_models.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/presentation/screens/route/payment_web_view_screen.dart';
import 'package:smartgo/presentation/screens/route/route_payment_result_screen.dart';

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
    _TicketOption(
      label: 'Vé lượt',
      description: 'Vé một lượt đi',
      price: 7000,
      ticketType: 'LUOT',
    ),
    _TicketOption(
      label: 'Vé HSSV',
      description: 'Vé dành cho học sinh, sinh viên',
      price: 3000,
      ticketType: 'HSSV',
    ),
    _TicketOption(
      label: 'Vé tháng',
      description: 'Vé sử dụng không giới hạn trong 30 ngày',
      price: 200000,
      ticketType: 'THANG',
    ),
    _TicketOption(
      label: 'Vé tập',
      description: 'Gói 25 lượt đi',
      price: 157500,
      ticketType: 'TAP',
    ),
  ];

  static const List<_PaymentMethodOption> _paymentMethods = [
    _PaymentMethodOption(
      id: _providerVnpay,
      label: 'VNPAY',
      description: 'Cổng thanh toán ngân hàng nội địa',
      icon: Icons.account_balance_wallet_outlined,
      foregroundColor: Color(0xFF0066CC),
      backgroundColor: Color(0xFFE8F0FB),
      supported: true,
    ),
    _PaymentMethodOption(
      id: _providerMomo,
      label: 'MoMo',
      description: 'Ví điện tử thanh toán nhanh',
      icon: Icons.account_balance_outlined,
      foregroundColor: Color(0xFFAE2070),
      backgroundColor: Color(0xFFFCE8F2),
      supported: true,
    ),
    _PaymentMethodOption(
      id: 'zalopay',
      label: 'ZaloPay',
      description: 'Ví điện tử Zalo',
      icon: Icons.wallet_outlined,
      foregroundColor: Color(0xFF006AF5),
      backgroundColor: Color(0xFFE6F0FF),
      supported: false,
    ),
  ];

  int _selectedTicketIndex = 0;
  int _quantity = 1;
  String _selectedProvider = _providerVnpay;
  bool _isSubmitting = false;

  final http.Client _client = http.Client();
  late final PaymentRemoteDataSource _paymentRemoteDataSource;
  late final BillsRemoteDataSource _billsRemoteDataSource;
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  int get _totalAmount =>
      _ticketOptions[_selectedTicketIndex].price * _quantity;

  @override
  void initState() {
    super.initState();
    _paymentRemoteDataSource = PaymentRemoteDataSourceImpl(client: _client);
    _billsRemoteDataSource = BillsRemoteDataSource(client: _client);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 12,
              16,
              190,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildRouteHeroCard(),
                const SizedBox(height: 16),
                _buildSectionHeader('Loại vé', Icons.confirmation_num_outlined),
                const SizedBox(height: 10),
                ..._ticketOptions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final selected = index == _selectedTicketIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildTicketOptionCard(
                      option: option,
                      selected: selected,
                      onTap: () => setState(() => _selectedTicketIndex = index),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                _buildSectionHeader('Số lượng', Icons.exposure_outlined),
                const SizedBox(height: 10),
                _buildQuantityCard(),
                const SizedBox(height: 16),
                _buildSectionHeader('Cổng thanh toán', Icons.payments_outlined),
                const SizedBox(height: 10),
                ..._paymentMethods.map((method) {
                  final selected = method.id == _selectedProvider;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildPaymentMethodCard(
                      method: method,
                      selected: selected,
                      onTap: method.supported
                          ? () => setState(() => _selectedProvider = method.id)
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _buildStickyPayBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  size: 18, color: Color(0xFF334155)),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mua vé',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              SizedBox(height: 2),
              Text(
                'Thanh toán vé xe buýt',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteHeroCard() {
    final routeColor = _getRouteColor(widget.route.routeCode);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [routeColor, routeColor.withValues(alpha: 0.88)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.route.routeCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.route.routeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.route.startPoint} → ${widget.route.endPoint}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildHeroMetric(Icons.schedule_rounded, widget.route.tripTime),
                const SizedBox(width: 16),
                _buildHeroMetric(
                  Icons.straighten_rounded,
                  '${widget.route.totalDistance.toStringAsFixed(1)} km',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroMetric(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0D9488)),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketOptionCard({
    required _TicketOption option,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final routeColor = _getRouteColor(widget.route.routeCode);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF0FDFA) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? routeColor : const Color(0xFFF1F5F9),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? routeColor : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                  color: selected ? routeColor : Colors.white,
                ),
                child: selected
                    ? const Center(
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF0F766E)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? const Color(0xFF14B8A6)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatVnd(option.price),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityCard() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStepperButton(
            icon: Icons.remove_rounded,
            onTap: _decreaseQuantity,
            enabled: _quantity > 1,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                '$_quantity',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildStepperButton(
            icon: Icons.add_rounded,
            onTap: _increaseQuantity,
            enabled: true,
            primary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
    bool primary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled
                ? (primary ? const Color(0xFF0D9488) : Colors.white)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? (primary
                      ? const Color(0xFF0D9488)
                      : const Color(0xFFE2E8F0))
                  : const Color(0xFFF1F5F9),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? (primary ? Colors.white : const Color(0xFF475569))
                : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard({
    required _PaymentMethodOption method,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final borderColor =
        selected ? const Color(0xFFCBD5E1) : const Color(0xFFF1F5F9);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF8FAFC) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: method.backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child:
                    Icon(method.icon, color: method.foregroundColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          method.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (!method.supported) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Text(
                              'Sắp ra mắt',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      method.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF0D9488)
                        : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Center(
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: Color(0xFF0D9488),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyPayBar() {
    final selectedLabel = _paymentMethods
        .firstWhere((method) => method.id == _selectedProvider)
        .label;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tổng thanh toán',
              style: TextStyle(
                color: Color(0xFFA7F3D0),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatVnd(_totalAmount),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Phương thức: $selectedLabel',
              style: const TextStyle(
                color: Color(0xFFCCFBF1),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _onProceedPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F766E),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.confirmation_num_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Thanh toán qua $selectedLabel',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRouteColor(String code) {
    final colors = [
      const Color(0xFF0F9B8E),
      const Color(0xFF2563EB),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
    ];
    return colors[code.hashCode.abs() % colors.length];
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

    final storage = getIt<StorageService>();
    final accessToken = storage.getAuthToken();
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
    final isMomo = _selectedProvider == _providerMomo;
    const platform = kIsWeb ? 'web' : 'app';

    late VnpayCreatePaymentResponse createResponse;

    try {
      final bill = await _billsRemoteDataSource.createBill(
        BillCreateRequest(
          routeId: widget.route.id,
          ticketType: selectedTicket.ticketType,
          quantity: _quantity,
          discountAmount: 0,
          metadata: {
            'routeCode': widget.route.routeCode,
            'ticketLabel': selectedTicket.label,
          },
        ),
        accessToken: accessToken,
      );

      await storage.saveString(AppConstants.pendingBillIdKey, bill.id);

      final billAmount = bill.totalAmount > 0 ? bill.totalAmount : _totalAmount;

      VnpayCreatePaymentRequest buildRequest({String? returnUrl}) {
        return VnpayCreatePaymentRequest(
          amount: billAmount,
          orderDescription:
              'Thanh toán ${selectedTicket.label} tuyến ${widget.route.routeCode} x$_quantity',
          orderType: 'other',
          billId: bill.id,
          bankCode: null,
          locale: 'vn',
          platform: platform,
          returnUrl: returnUrl,
        );
      }

      Future<VnpayCreatePaymentResponse> createPayment(
        VnpayCreatePaymentRequest request,
      ) {
        return isMomo
            ? _paymentRemoteDataSource.createMomoPayment(
                request,
                accessToken,
              )
            : _paymentRemoteDataSource.createVnpayPayment(
                request,
                accessToken,
              );
      }

      final requestedReturnUrl = _buildReturnUrl(
        isMomo: isMomo,
        billId: bill.id,
      );
      try {
        createResponse = await createPayment(
          buildRequest(returnUrl: requestedReturnUrl),
        );
      } on BadRequestException {
        createResponse = await createPayment(buildRequest());
      }

      final paymentUri = Uri.tryParse(createResponse.paymentUrl);
      if (paymentUri == null) {
        throw Exception('Liên kết thanh toán không hợp lệ');
      }

      await _openPaymentPage(paymentUri);

      if (kIsWeb) {
        // Web flow continues in the same tab and should return via callback route.
        return;
      }

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RoutePaymentResultScreen(
            route: widget.route,
            ticketLabel: selectedTicket.label,
            quantity: _quantity,
            selectedBank: _selectedProvider,
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
    if (kIsWeb) {
      // Redirect in the same tab so payment provider can return to callback directly.
      final opened = await openExternalUrl(paymentUri, webTarget: '_self');
      if (!opened) {
        throw Exception('Không thể mở trang thanh toán $_selectedProvider');
      }
      return;
    }
    // On mobile, open payment in an in-app WebView so we can intercept
    // the backend return URL and navigate back into the app automatically.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PaymentWebViewScreen(
        initialUrl: paymentUri,
        provider: _selectedProvider.toLowerCase(),
      ),
    ));
  }

  String _buildReturnUrl({required bool isMomo, String? billId}) {
    final callbackPath =
        isMomo ? AppRoutes.momoPaymentCallback : AppRoutes.vnpayPaymentCallback;

    if (kIsWeb) {
      final origin = Uri.base.origin;
      final uri = Uri.parse('$origin$callbackPath').replace(
        queryParameters:
            billId == null || billId.isEmpty ? null : {'billId': billId},
      );
      return uri.toString();
    }

    final returnPath = isMomo
        ? '/api/v1/payments/momo/return/app'
        : '/api/v1/payments/vnpay/return/app';
    final uri = Uri.parse('${AppEnv.baseUrl}$returnPath').replace(
      queryParameters:
          billId == null || billId.isEmpty ? null : {'billId': billId},
    );
    return uri.toString();
  }
}

class _TicketOption {
  final String label;
  final String description;
  final int price;
  final String ticketType;

  const _TicketOption({
    required this.label,
    required this.description,
    required this.price,
    required this.ticketType,
  });
}

class _PaymentMethodOption {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final bool supported;

  const _PaymentMethodOption({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.supported,
  });
}
