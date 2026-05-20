import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/di/injection.dart';
import '../../../data/datasources/bills_remote_data_source.dart';
import '../../../data/models/bill_models.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/loading_indicator.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  static const String _statusAllKey = 'all';
  static const String _statusPendingKey = 'PENDING';
  static const String _statusPaidKey = 'PAID';
  static const String _statusFailedKey = 'FAILED';
  static const String _statusExpiredKey = 'EXPIRED';
  static const int _defaultLimit = 30;

  late final BillsRemoteDataSource _dataSource;
  final Map<String, Future<BillsPageResponse>> _billFutures = {};
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');
  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    _dataSource = BillsRemoteDataSource(client: getIt<http.Client>());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _activeUserId ??= authState.user.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        final nextUserId = state is AuthAuthenticated ? state.user.id : null;
        if (nextUserId != _activeUserId) {
          if (!mounted) {
            return;
          }
          setState(() {
            _activeUserId = nextUserId;
            _billFutures.clear();
          });
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: UIConstants.scaffoldBackground,
          appBar: AppBar(
            title: const Text(
              'Vé & Hóa đơn',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go(AppRoutes.home);
                }
              },
            ),
            bottom: const TabBar(
              labelColor: UIConstants.textPrimary,
              unselectedLabelColor: UIConstants.textSecondary,
              indicatorColor: UIConstants.primaryTeal,
              labelStyle: TextStyle(fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'Vé của tôi'),
                Tab(text: 'Danh sách hóa đơn'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildTicketsTab(authState),
              _buildBillsTab(authState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketsTab(AuthState authState) {
    if (authState is! AuthAuthenticated) {
      return _buildAuthRequiredState(
        'Vui lòng đăng nhập để xem vé của bạn.',
      );
    }

    final future = _billFuture(
      _statusPaidKey,
      status: _statusPaidKey,
    );

    return FutureBuilder<BillsPageResponse>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }

        if (snapshot.hasError) {
          return _buildErrorState(
            message: 'Không tải được vé của bạn. Vui lòng thử lại.',
            onRetry: () => _refreshBills(
              _statusPaidKey,
              status: _statusPaidKey,
            ),
          );
        }

        final bills = snapshot.data?.data ?? const <BillModel>[];
        final tickets = _extractTickets(bills);

        if (tickets.isEmpty) {
          return _buildEmptyScroll(
            'Chưa có vé đã thanh toán.',
          );
        }

        return RefreshIndicator(
          onRefresh: () => _refreshBills(
            _statusPaidKey,
            status: _statusPaidKey,
          ),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            itemBuilder: (context, index) {
              return _buildTicketCard(tickets[index]);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemCount: tickets.length,
          ),
        );
      },
    );
  }

  Widget _buildBillsTab(AuthState authState) {
    if (authState is! AuthAuthenticated) {
      return _buildAuthRequiredState(
        'Vui lòng đăng nhập để xem lịch sử hóa đơn.',
      );
    }

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: UIConstants.borderLight),
              ),
              child: TabBar(
                labelColor: UIConstants.textPrimary,
                unselectedLabelColor: UIConstants.textSecondary,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                indicator: BoxDecoration(
                  color: UIConstants.scaffoldBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: UIConstants.borderLight),
                ),
                tabs: const [
                  Tab(text: 'Tất cả'),
                  Tab(text: 'Chờ TT'),
                  Tab(text: 'Đã TT'),
                  Tab(text: 'Thất bại'),
                  Tab(text: 'Hết hạn'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _buildBillsList(
                  statusKey: _statusAllKey,
                ),
                _buildBillsList(
                  statusKey: _statusPendingKey,
                  status: _statusPendingKey,
                ),
                _buildBillsList(
                  statusKey: _statusPaidKey,
                  status: _statusPaidKey,
                ),
                _buildBillsList(
                  statusKey: _statusFailedKey,
                  status: _statusFailedKey,
                ),
                _buildBillsList(
                  statusKey: _statusExpiredKey,
                  status: _statusExpiredKey,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillsList({
    required String statusKey,
    String? status,
  }) {
    final future = _billFuture(statusKey, status: status);

    return FutureBuilder<BillsPageResponse>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }

        if (snapshot.hasError) {
          return _buildErrorState(
            message: 'Không tải được hóa đơn. Vui lòng thử lại.',
            onRetry: () => _refreshBills(statusKey, status: status),
          );
        }

        final bills = snapshot.data?.data ?? const <BillModel>[];
        if (bills.isEmpty) {
          return _buildEmptyScroll('Chưa có hóa đơn nào.');
        }

        return RefreshIndicator(
          onRefresh: () => _refreshBills(statusKey, status: status),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            itemBuilder: (context, index) {
              return _buildBillCard(bills[index]);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: bills.length,
          ),
        );
      },
    );
  }

  Widget _buildAuthRequiredState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: UIConstants.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState({
    required String message,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: UIConstants.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScroll(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
      children: [
        Center(
          child: Column(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: UIConstants.iconMuted,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: UIConstants.textSecondary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTicketCard(_TicketEntry entry) {
    final ticket = entry.ticket;
    final bill = entry.bill;
    final ticketType =
        ticket.ticketType.isNotEmpty ? ticket.ticketType : bill.ticketType;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: UIConstants.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: UIConstants.primaryTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_bus_filled_rounded,
                    color: UIConstants.primaryTeal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ticketTypeLabel(ticketType).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: UIConstants.textPrimary,
                        ),
                      ),
                      if (bill.route?.routeName != null &&
                          bill.route!.routeName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _stripRouteNamePrefix(bill.route!.routeName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: UIConstants.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildStatusPill(
                  label: _ticketStatusLabel(ticket.ticketStatus),
                  color: _ticketStatusColor(ticket.ticketStatus),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildTicketQr(ticket),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    children: [
                      _buildTicketMetaRow('Mã vé', ticket.ticketCode,
                          isBold: true),
                      if (bill.billCode.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildTicketMetaRow('Hóa đơn', bill.billCode),
                      ],
                      if (ticket.remainingTrips > 0) ...[
                        const SizedBox(height: 8),
                        _buildTicketMetaRow(
                          'Số lượt còn lại',
                          ticket.remainingTrips.toString(),
                          valueColor: UIConstants.primaryTeal,
                          isBold: true,
                        ),
                      ],
                      if (ticket.expiredAt != null) ...[
                        const SizedBox(height: 8),
                        _buildTicketMetaRow(
                          'Hết hạn',
                          _formatDateTime(ticket.expiredAt!),
                        ),
                      ],
                      if (bill.paidAt != null) ...[
                        const SizedBox(height: 8),
                        _buildTicketMetaRow(
                          'Thanh toán',
                          _formatDateTime(bill.paidAt!),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketQr(TicketModel ticket) {
    final qrPayload = ticket.qrPayload?.trim();
    if (qrPayload != null && qrPayload.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showZoomedQr(context, ticket),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: UIConstants.borderLight),
          ),
          child: QrImageView(
            data: qrPayload,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
          ),
        ),
      );
    }

    final imageUrl = ticket.qrImageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showZoomedQr(context, ticket),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: UIConstants.borderLight),
          ),
          child: Image.network(
            imageUrl,
            width: 180,
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Text(
                'Không tải được mã QR',
                style: TextStyle(color: UIConstants.textSecondary),
              );
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: UIConstants.scaffoldBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UIConstants.borderLight),
      ),
      child: const Text(
        'Chưa có mã QR',
        style: TextStyle(color: UIConstants.textSecondary),
      ),
    );
  }

  void _showZoomedQr(BuildContext context, TicketModel ticket) {
    final qrPayload = ticket.qrPayload?.trim();
    final imageUrl = ticket.qrImageUrl?.trim();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (qrPayload != null && qrPayload.isNotEmpty)
                  QrImageView(
                    data: qrPayload,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                  )
                else if (imageUrl != null && imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                  ),
                const SizedBox(height: 24),
                Text(
                  ticket.ticketCode,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đưa mã này cho nhân viên kiểm soát',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: UIConstants.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTicketMetaRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              color: UIConstants.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? UIConstants.textPrimary,
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBillCard(BillModel bill) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: UIConstants.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: UIConstants.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.billCode.isNotEmpty ? bill.billCode : 'Hóa đơn',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: UIConstants.textPrimary,
                      ),
                    ),
                    if (bill.route?.routeName != null &&
                        bill.route!.routeName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _stripRouteNamePrefix(bill.route!.routeName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: UIConstants.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBillDate(bill),
                      style: const TextStyle(
                          color: UIConstants.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _buildStatusPill(
                label: _billStatusLabel(bill.status),
                color: _billStatusColor(bill.status),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: UIConstants.borderLight),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loại vé: ${_ticketTypeLabel(bill.ticketType)}',
                      style: const TextStyle(
                        color: UIConstants.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (bill.quantity > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Số lượng: ${bill.quantity}',
                        style: const TextStyle(
                          color: UIConstants.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Tổng tiền',
                    style: TextStyle(
                      color: UIConstants.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_currencyFormat.format(bill.totalAmount)}đ',
                    style: const TextStyle(
                      color: UIConstants.primaryTeal,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if ((bill.txnRef ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag, size: 14, color: UIConstants.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mã GD: ${bill.txnRef}',
                      style: const TextStyle(
                        color: UIConstants.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<_TicketEntry> _extractTickets(List<BillModel> bills) {
    final entries = <_TicketEntry>[];
    for (final bill in bills) {
      if (bill.status.toUpperCase() != _statusPaidKey) {
        continue;
      }
      for (final ticket in bill.tickets) {
        entries.add(_TicketEntry(bill: bill, ticket: ticket));
      }
    }
    return entries;
  }

  Future<BillsPageResponse> _loadBills({
    String? status,
  }) {
    return _dataSource.getBills(
      page: 1,
      limit: _defaultLimit,
      status: status,
      orderBy: 'createdAt',
      orderDirection: 'desc',
    );
  }

  Future<BillsPageResponse> _billFuture(
    String statusKey, {
    String? status,
  }) {
    return _billFutures.putIfAbsent(
      statusKey,
      () => _loadBills(status: status),
    );
  }

  Future<void> _refreshBills(
    String statusKey, {
    String? status,
  }) async {
    final future = _loadBills(status: status);
    setState(() {
      _billFutures[statusKey] = future;
    });
    await future;
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime.toLocal());
  }

  String _stripRouteNamePrefix(String routeName) {
    return routeName.replaceFirst(RegExp(r'^(Lượt đi|Lượt về):\s*'), '');
  }

  String _formatBillDate(BillModel bill) {
    final dateTime = bill.paidAt ?? bill.createdAt;
    if (dateTime == null) {
      return 'Chưa có thời gian';
    }
    return _formatDateTime(dateTime);
  }

  String _ticketTypeLabel(String rawType) {
    switch (rawType.toUpperCase()) {
      case 'HSSV':
        return 'Vé HSSV';
      case 'THANG':
        return 'Vé tháng';
      case 'TAP':
        return 'Vé tập';
      case 'LUOT':
        return 'Vé lượt';
      default:
        return rawType.isNotEmpty ? rawType : 'Vé';
    }
  }

  String _billStatusLabel(String rawStatus) {
    switch (rawStatus.toUpperCase()) {
      case 'PENDING':
        return 'Chờ TT';
      case 'PAID':
        return 'Đã TT';
      case 'FAILED':
        return 'Thất bại';
      case 'CANCELLED':
        return 'Đã hủy';
      case 'EXPIRED':
        return 'Hết hạn';
      case 'REFUNDED':
        return 'Hoàn tiền';
      default:
        return rawStatus.isNotEmpty ? rawStatus : 'Không rõ';
    }
  }

  Color _billStatusColor(String rawStatus) {
    switch (rawStatus.toUpperCase()) {
      case 'PAID':
        return UIConstants.primaryTeal;
      case 'PENDING':
        return const Color(0xFFF59E0B);
      case 'FAILED':
        return UIConstants.danger;
      case 'CANCELLED':
      case 'EXPIRED':
        return const Color(0xFF64748B);
      case 'REFUNDED':
        return const Color(0xFF0EA5E9);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  String _ticketStatusLabel(String rawStatus) {
    switch (rawStatus.toUpperCase()) {
      case 'ACTIVE':
        return 'Còn hiệu lực';
      case 'USED':
        return 'Đã dùng';
      case 'EXPIRED':
        return 'Hết hạn';
      default:
        return rawStatus.isNotEmpty ? rawStatus : 'Không rõ';
    }
  }

  Color _ticketStatusColor(String rawStatus) {
    switch (rawStatus.toUpperCase()) {
      case 'ACTIVE':
        return UIConstants.primaryTeal;
      case 'USED':
        return const Color(0xFF0EA5E9);
      case 'EXPIRED':
        return UIConstants.danger;
      default:
        return const Color(0xFF94A3B8);
    }
  }
}

class _TicketEntry {
  final BillModel bill;
  final TicketModel ticket;

  const _TicketEntry({
    required this.bill,
    required this.ticket,
  });
}
