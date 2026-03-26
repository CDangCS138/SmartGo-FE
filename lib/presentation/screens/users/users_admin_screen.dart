import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/data/datasources/users_remote_data_source.dart';
import 'package:smartgo/data/models/users_models.dart';

class UsersAdminScreen extends StatefulWidget {
  const UsersAdminScreen({super.key});

  @override
  State<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends State<UsersAdminScreen> {
  static const Color _ink = Color(0xFF1A2740);
  static const Color _inkSoft = Color(0xFF2A3E63);
  static const Color _gold = Color(0xFFC6A86E);
  static const Color _fog = Color(0xFFF7FAFF);

  final http.Client _client = http.Client();
  late final UsersRemoteDataSource _usersDataSource;

  List<AdminUserModel> _users = const [];
  bool _isLoading = true;
  bool _isBusy = false;
  int _page = 1;
  final int _limit = 10;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usersDataSource = UsersRemoteDataSource(client: _client);
    _loadUsers();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadUsers({int? targetPage}) async {
    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      if (targetPage != null) {
        _page = targetPage;
      }
    });

    try {
      final result = await _usersDataSource.getUsers(
        accessToken: token,
        page: _page,
        limit: _limit,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = result.data;
        _total = result.total;
        _page = result.page;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Không tải được danh sách người dùng: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createUser() async {
    final form = await _showUserFormSheet();
    if (form == null) {
      return;
    }

    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.isEmpty) {
      _showToast('Thiếu access token');
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _usersDataSource.createUser(
        accessToken: token,
        email: form.email,
        name: form.name,
        role: form.role,
        avatar: form.avatar!,
      );

      if (!mounted) {
        return;
      }

      _showToast('Tạo user thành công');
      await _loadUsers(targetPage: 1);
    } catch (e) {
      _showToast('Tạo user thất bại: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _editUser(AdminUserModel user) async {
    final form = await _showUserFormSheet(seed: user, avatarRequired: true);
    if (form == null) {
      return;
    }

    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.isEmpty) {
      _showToast('Thiếu access token');
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _usersDataSource.updateUser(
        accessToken: token,
        id: user.id,
        email: form.email,
        name: form.name,
        role: form.role,
        avatar: form.avatar!,
      );

      if (!mounted) {
        return;
      }

      _showToast('Cập nhật user thành công');
      await _loadUsers();
    } catch (e) {
      _showToast('Cập nhật user thất bại: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _viewUser(AdminUserModel user) async {
    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.isEmpty) {
      _showToast('Thiếu access token');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final detail = await _usersDataSource.getUserById(
        accessToken: token,
        id: user.id,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: _fog,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Chi tiết người dùng'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('ID', detail.id),
                _detail('Tên', detail.name),
                _detail('Email', detail.email),
                _detail('Role', detail.role),
                _detail('Created by', detail.createdBy ?? '-'),
                _detail('Updated by', detail.updatedBy ?? '-'),
                _detail('Created at', _fmt(detail.createdAt)),
                _detail('Updated at', _fmt(detail.updatedAt)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _showToast('Không lấy được chi tiết user: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _deleteUser(AdminUserModel user) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xóa người dùng'),
            content: Text('Bạn có chắc muốn xóa ${user.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Xóa'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) {
      return;
    }

    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.isEmpty) {
      _showToast('Thiếu access token');
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _usersDataSource.deleteUser(accessToken: token, id: user.id);
      _showToast('Đã xóa user');
      await _loadUsers();
    } catch (e) {
      _showToast('Xóa user thất bại: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<_UserFormResult?> _showUserFormSheet({
    AdminUserModel? seed,
    bool avatarRequired = true,
  }) async {
    final nameCtl = TextEditingController(text: seed?.name ?? '');
    final emailCtl = TextEditingController(text: seed?.email ?? '');
    final roleCtl = TextEditingController(text: seed?.role ?? 'member');
    XFile? avatar;

    final formResult = await showModalBottomSheet<_UserFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final formKey = GlobalKey<FormState>();
        Uint8List? avatarPreview;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickAvatar() async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 90,
                maxWidth: 1080,
              );

              if (picked == null) {
                return;
              }

              avatar = picked;
              avatarPreview = await picked.readAsBytes();
              setModalState(() {});
            }

            return Container(
              margin: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _fog,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _gold.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        seed == null
                            ? 'Tạo người dùng mới'
                            : 'Cập nhật người dùng',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _field(
                        controller: nameCtl,
                        label: 'Họ tên',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập họ tên'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: emailCtl,
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) {
                            return 'Nhập email';
                          }
                          final atIndex = value.indexOf('@');
                          final dotIndex = value.lastIndexOf('.');
                          final ok = atIndex > 0 &&
                              dotIndex > atIndex + 1 &&
                              dotIndex < value.length - 1;
                          return ok ? null : 'Email không hợp lệ';
                        },
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: roleCtl,
                        label: 'Role (admin/member)',
                        validator: (v) {
                          final value = (v ?? '').trim().toLowerCase();
                          if (value != 'admin' && value != 'member') {
                            return 'Role chỉ nhận admin hoặc member';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _ink,
                                side: BorderSide(
                                    color: _gold.withValues(alpha: 0.6)),
                              ),
                              onPressed: pickAvatar,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(
                                avatar == null ? 'Chọn avatar' : avatar!.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (avatarPreview != null) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: CircleAvatar(
                            radius: 32,
                            backgroundImage: MemoryImage(avatarPreview!),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Hủy'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _ink,
                                foregroundColor: _gold,
                              ),
                              onPressed: () {
                                final valid =
                                    formKey.currentState?.validate() ?? false;
                                if (!valid) {
                                  return;
                                }

                                if (avatarRequired && avatar == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Vui lòng chọn avatar'),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.of(context).pop(
                                  _UserFormResult(
                                    name: nameCtl.text.trim(),
                                    email: emailCtl.text.trim(),
                                    role: roleCtl.text.trim().toLowerCase(),
                                    avatar: avatar,
                                  ),
                                );
                              },
                              child:
                                  Text(seed == null ? 'Tạo mới' : 'Cập nhật'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return formResult;
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _inkSoft.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _inkSoft.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _ink, width: 1.3),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }

  String _fmt(DateTime? date) {
    if (date == null) {
      return '-';
    }
    return date.toLocal().toString();
  }

  void _showToast(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxPage = (_total / _limit).ceil().clamp(1, 99999);

    return Scaffold(
      backgroundColor: _fog,
      appBar: AppBar(
        backgroundColor: _fog,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Users Studio',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _createUser,
        backgroundColor: _gold,
        foregroundColor: _ink,
        icon: const Icon(Icons.add),
        label: const Text(
          'Tạo user',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -90,
            right: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -110,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDDE7FA).withValues(alpha: 0.45),
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: _loadUsers,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _buildHeaderCard(maxPage),
                const SizedBox(height: 14),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 52),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _buildErrorCard()
                else if (_users.isEmpty)
                  _buildEmptyCard()
                else
                  ..._users.map(_buildUserCard),
              ],
            ),
          ),
          if (_isBusy)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(int maxPage) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF6EFD9), Color(0xFFEEF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bảng điều khiển người dùng',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tổng cộng $_total tài khoản',
            style: const TextStyle(color: Color(0xFF5A6678)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: BorderSide(color: _ink.withValues(alpha: 0.3)),
                  ),
                  onPressed: (_page <= 1 || _isLoading)
                      ? null
                      : () => _loadUsers(targetPage: _page - 1),
                  icon: const Icon(Icons.west),
                  label: const Text('Trang trước'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: BorderSide(color: _ink.withValues(alpha: 0.3)),
                  ),
                  onPressed: (_page >= maxPage || _isLoading)
                      ? null
                      : () => _loadUsers(targetPage: _page + 1),
                  icon: const Icon(Icons.east),
                  label: const Text('Trang sau'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Trang $_page / $maxPage · $_limit bản ghi mỗi trang',
            style: const TextStyle(color: Color(0xFF5A6678)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Không thể tải dữ liệu',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: Color(0xFF891919)),
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? 'Unknown error',
            style: const TextStyle(color: Color(0xFF7A2D2D)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _loadUsers,
            style: FilledButton.styleFrom(backgroundColor: _gold),
            child: const Text('Thử lại', style: TextStyle(color: _ink)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F1)),
      ),
      child: const Column(
        children: [
          Icon(Icons.people_alt_outlined, size: 52, color: Color(0xFF8A96AA)),
          SizedBox(height: 8),
          Text(
            'Danh sách người dùng đang trống',
            style: TextStyle(
                color: Color(0xFF4F5C70), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(AdminUserModel user) {
    final initials = user.name.trim().isEmpty
        ? '?'
        : user.name.trim().split(' ').map((e) => e[0]).take(2).join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _inkSoft,
            backgroundImage:
                (user.avatar != null && user.avatar!.trim().isNotEmpty)
                    ? NetworkImage(user.avatar!)
                    : null,
            child: (user.avatar == null || user.avatar!.trim().isEmpty)
                ? Text(
                    initials.toUpperCase(),
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w700,
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
                  user.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: const TextStyle(
                    color: Color(0xFF5B6677),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _ink.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    user.role.toUpperCase(),
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'view') {
                _viewUser(user);
              } else if (value == 'edit') {
                _editUser(user);
              } else if (value == 'delete') {
                _deleteUser(user);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'view', child: Text('Xem chi tiết')),
              PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
              PopupMenuItem(value: 'delete', child: Text('Xóa')),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserFormResult {
  final String name;
  final String email;
  final String role;
  final XFile? avatar;

  const _UserFormResult({
    required this.name,
    required this.email,
    required this.role,
    required this.avatar,
  });
}
