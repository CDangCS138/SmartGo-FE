import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/datasources/notifications_remote_data_source.dart';
import '../../../data/models/notification_models.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/loading_indicator.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const String _typeAllKey = 'all';
  static const String _typePaymentKey = 'PAYMENT_SUCCESS';
  static const String _typeBillKey = 'BILL_CREATED';
  static const String _typeSystemKey = 'SYSTEM';
  static const int _defaultLimit = 30;

  late final NotificationsRemoteDataSource _dataSource;
  final Map<String, Future<NotificationsPageResponse>> _notificationFutures =
      {};
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  String? _activeUserId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _dataSource = NotificationsRemoteDataSource(client: getIt<http.Client>());
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            _notificationFutures.clear();
          });
        }
      },
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: UIConstants.scaffoldBackground,
          appBar: AppBar(
            title: const Text(
              'Thông báo',
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
              isScrollable: true,
              labelColor: UIConstants.textPrimary,
              unselectedLabelColor: UIConstants.textSecondary,
              indicatorColor: UIConstants.primaryTeal,
              labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(text: 'Tất cả'),
                Tab(text: 'Thanh toán'),
                Tab(text: 'Hóa đơn'),
                Tab(text: 'Hệ thống'),
              ],
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tiêu đề hoặc nội dung...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _clearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: UIConstants.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: UIConstants.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: UIConstants.primaryTeal,
                        width: 1.5,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _applySearch,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: authState is! AuthAuthenticated
                    ? _buildAuthRequiredState(
                        'Vui lòng đăng nhập để xem thông báo.',
                      )
                    : TabBarView(
                        children: [
                          _buildNotificationsList(typeKey: _typeAllKey),
                          _buildNotificationsList(
                            typeKey: _typePaymentKey,
                            type: _typePaymentKey,
                          ),
                          _buildNotificationsList(
                            typeKey: _typeBillKey,
                            type: _typeBillKey,
                          ),
                          _buildNotificationsList(
                            typeKey: _typeSystemKey,
                            type: _typeSystemKey,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsList({
    required String typeKey,
    String? type,
  }) {
    final future = _notificationFuture(typeKey, type: type);

    return FutureBuilder<NotificationsPageResponse>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }

        if (snapshot.hasError) {
          return _buildErrorState(
            message: 'Không tải được thông báo. Vui lòng thử lại.',
            onRetry: () => _refreshNotifications(typeKey, type: type),
          );
        }

        final notifications =
            snapshot.data?.data ?? const <NotificationModel>[];
        if (notifications.isEmpty) {
          return _buildEmptyScroll('Chưa có thông báo nào.');
        }

        return RefreshIndicator(
          onRefresh: () => _refreshNotifications(typeKey, type: type),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemBuilder: (context, index) {
              return _buildNotificationCard(notifications[index]);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: notifications.length,
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    final typeColor = _typeColor(notification.type);
    final typeLabel = _typeLabel(notification.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: UIConstants.borderLight,
        ),
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
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _typeIcon(notification.type),
                  color: typeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title.isNotEmpty
                          ? notification.title
                          : 'Thông báo',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: UIConstants.textPrimary,
                      ),
                    ),
                    if (notification.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _dateFormat.format(
                          notification.createdAt!.toLocal(),
                        ),
                        style: const TextStyle(
                          color: UIConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _buildTypePill(label: typeLabel, color: typeColor),
            ],
          ),
          if (notification.content.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: UIConstants.borderLight),
            ),
            Text(
              notification.content,
              style: const TextStyle(
                color: UIConstants.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypePill({required String label, required Color color}) {
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
                Icons.notifications_none_rounded,
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

  Future<NotificationsPageResponse> _loadNotifications({
    String? type,
    String? accessToken,
  }) {
    return _dataSource.getNotifications(
      page: 1,
      limit: _defaultLimit,
      search: _searchQuery.isEmpty ? null : _searchQuery,
      searchFields: 'title,content',
      type: type,
      orderBy: 'createdAt',
      orderDirection: 'desc',
      accessToken: accessToken,
    );
  }

  String _cacheKey(String typeKey) {
    return '$typeKey::$_searchQuery';
  }

  Future<NotificationsPageResponse> _notificationFuture(
    String typeKey, {
    String? type,
  }) {
    final authState = context.read<AuthBloc>().state;
    final accessToken = authState is AuthAuthenticated ? authState.accessToken : null;

    return _notificationFutures.putIfAbsent(
      _cacheKey(typeKey),
      () => _loadNotifications(type: type, accessToken: accessToken),
    );
  }

  Future<void> _refreshNotifications(
    String typeKey, {
    String? type,
  }) async {
    final authState = context.read<AuthBloc>().state;
    final accessToken = authState is AuthAuthenticated ? authState.accessToken : null;

    final future = _loadNotifications(type: type, accessToken: accessToken);
    setState(() {
      _notificationFutures[_cacheKey(typeKey)] = future;
    });
    await future;
  }

  void _applySearch(String value) {
    final nextQuery = value.trim();
    if (nextQuery == _searchQuery) {
      return;
    }
    setState(() {
      _searchQuery = nextQuery;
      _notificationFutures.clear();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    if (_searchQuery.isEmpty) {
      return;
    }
    setState(() {
      _searchQuery = '';
      _notificationFutures.clear();
    });
  }

  String _typeLabel(NotificationType type) {
    switch (type) {
      case NotificationType.paymentSuccess:
        return 'Thanh toán';
      case NotificationType.billCreated:
        return 'Hóa đơn';
      case NotificationType.system:
        return 'Hệ thống';
      case NotificationType.unknown:
        return 'Khác';
    }
  }

  Color _typeColor(NotificationType type) {
    switch (type) {
      case NotificationType.paymentSuccess:
        return UIConstants.primaryTeal;
      case NotificationType.billCreated:
        return const Color(0xFF2563EB);
      case NotificationType.system:
        return const Color(0xFFF59E0B);
      case NotificationType.unknown:
        return const Color(0xFF94A3B8);
    }
  }

  IconData _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.paymentSuccess:
        return Icons.payments_outlined;
      case NotificationType.billCreated:
        return Icons.receipt_long_outlined;
      case NotificationType.system:
        return Icons.info_outline_rounded;
      case NotificationType.unknown:
        return Icons.notifications_none_rounded;
    }
  }
}
