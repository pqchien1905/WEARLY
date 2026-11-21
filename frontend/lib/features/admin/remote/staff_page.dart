import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/account_state.dart';
import '../../../app/api_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'operations_widgets.dart';

const _roleDescriptions = {
  'ADMIN': 'Toàn quyền quản trị, bao gồm nhân sự và vận hành hệ thống.',
  'MANAGER': 'Quản lý cửa hàng, sản phẩm, đơn hàng, khách hàng và nội dung.',
  'WAREHOUSE': 'Theo dõi kho, xử lý giao hàng và nhận hàng trả lại.',
  'SUPPORT': 'Tra cứu đơn hàng và phản hồi yêu cầu hỗ trợ.',
  'CUSTOMER': 'Mua sắm tại cửa hàng, không có quyền truy cập trang quản trị.',
};

final staffListProvider = FutureProvider.autoDispose
    .family<AdminPage, ({String email, int page, int limit})>(
      (ref, key) => ref
          .watch(adminRepositoryProvider)
          .staff(email: key.email, page: key.page, limit: key.limit),
    );

class RemoteStaffPage extends ConsumerStatefulWidget {
  const RemoteStaffPage({super.key});
  @override
  ConsumerState<RemoteStaffPage> createState() => _RemoteStaffPageState();
}

class _RemoteStaffPageState extends ConsumerState<RemoteStaffPage> {
  final email = TextEditingController(), form = GlobalKey<FormState>();
  String query = '';
  String? routeEmail;
  int page = 1, limit = 10;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final value = GoRouterState.of(context).uri.queryParameters['email'] ?? '';
    if (routeEmail != value) {
      routeEmail = value;
      email.text = value;
      query = value;
      page = 1;
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  void reload() => ref.invalidate(staffListProvider);
  void search() {
    if (!form.currentState!.validate()) return;
    setState(() {
      query = email.text.trim().toLowerCase();
      page = 1;
    });
  }

  void reset() {
    form.currentState?.reset();
    email.clear();
    setState(() {
      query = '';
      page = 1;
    });
    reload();
  }

  Future<void> edit(AdminRecord row) async {
    var role = row['role'] as String, active = row['active'] as bool;
    final repo = ref.read(adminRepositoryProvider);
    final self = row['id'] == ref.read(adminAccountProvider)?.id;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminMutationDialog(
        title: 'Đổi quyền',
        message:
            'Đổi quyền hoặc trạng thái sẽ kết thúc các phiên đăng nhập của tài khoản này. Luôn giữ ít nhất một quản trị viên đang hoạt động.',
        reload: reload,
        fields: [
          OperationsIdentity(
            name: row['name'],
            email: row['email'],
            caption: row['username'] == null ? null : '@${row['username']}',
          ),
          StatefulBuilder(
            builder: (context, update) => Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Vai trò'),
                  items: staffRoleNames.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) update(() => role = value);
                  },
                ),
                const SizedBox(height: 12),
                Text(_roleDescriptions[role] ?? '', style: T.small),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tài khoản hoạt động'),
                  value: active,
                  onChanged: (value) => update(() => active = value),
                ),
              ],
            ),
          ),
        ],
        submit: () async {
          await repo.updateStaff(
            row['id'],
            role: role,
            active: active,
            version: row['staffVersion'],
          );
        },
      ),
    );
    if (!mounted || changed != true) return;
    if (self && (role != row['role'] || active != row['active'])) {
      ref.read(adminSessionTokensProvider).clear();
    } else {
      reload();
      ref.invalidate(adminListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = staffListProvider((
      email: query,
      page: page,
      limit: limit,
    ));
    final value = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Nhân sự & quyền truy cập',
          'Quản lý tài khoản nhân sự, vai trò và quyền truy cập cửa hàng.',
          actions: [
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              busy: value.isLoading,
              onPressed: reload,
            ),
          ],
        ),
        AdminCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminSectionTitle('Tra cứu tài khoản'),
                const Text(
                  'Nhập chính xác email của tài khoản đã đăng ký để xem hoặc cấp quyền.',
                  style: T.small,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) {
                    final field = TextFormField(
                      key: const PageStorageKey('staff-email-search'),
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.search,
                      onFieldSubmitted: (_) => search(),
                      decoration: const InputDecoration(
                        labelText: 'Email tài khoản',
                        hintText: 'nhanvien@example.com',
                        prefixIcon: Icon(Icons.search),
                        counterText: '',
                      ),
                      maxLength: 254,
                      validator: (v) =>
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch((v ?? '').trim())
                          ? null
                          : 'Nhập email hợp lệ.',
                    );
                    final actions = Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        AppButton(
                          'Tìm tài khoản',
                          icon: Icons.search,
                          onPressed: value.isLoading ? null : search,
                        ),
                        AppButton(
                          'Hiển thị nhân sự',
                          outlined: true,
                          onPressed: value.isLoading ? null : reset,
                        ),
                      ],
                    );
                    return c.maxWidth >= 900 &&
                            MediaQuery.textScalerOf(context).scale(14) <= 18
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: field),
                              const SizedBox(width: 16),
                              actions,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              field,
                              const SizedBox(height: 16),
                              actions,
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
        ),
        AdminAsync(
          value: value,
          reload: reload,
          builder: (data) => OperationsPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminSectionTitle(
                  query.isEmpty ? 'Danh sách nhân sự' : 'Kết quả tra cứu',
                  action: Text(
                    '${adminNumber(data.total)} tài khoản',
                    style: T.small,
                  ),
                ),
                if (data.items.isEmpty)
                  const OperationsEmpty(
                    title: 'Không tìm thấy tài khoản.',
                    message:
                        'Kiểm tra lại email hoặc chọn “Hiển thị nhân sự” để xem toàn bộ danh sách.',
                    icon: Icons.person_search_outlined,
                  )
                else
                  OperationsTable(
                    headers: const [
                      'Nhân sự',
                      'Vai trò',
                      'Trạng thái',
                      'Thao tác',
                    ],
                    widths: const [3.4, 1.8, 2.2, 1.5],
                    rows: [
                      for (final row in data.items)
                        [
                          _identity(row),
                          _role(row),
                          _status(row),
                          _editButton(row),
                        ],
                    ],
                    cards: [
                      for (final row in data.items)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _identity(row),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [_role(row), _status(row)],
                            ),
                            const SizedBox(height: 8),
                            _editButton(row),
                          ],
                        ),
                    ],
                  ),
                AdminPagination(
                  page: data,
                  loading: value.isLoading,
                  onPage: (n) => setState(() => page = n),
                  onPageSize: (n) => setState(() {
                    limit = n;
                    page = 1;
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        OperationsPanel(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            key: const PageStorageKey('staff-role-guide'),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: const Icon(
              Icons.admin_panel_settings_outlined,
              color: T.accent,
            ),
            title: Text(
              'Hướng dẫn phân quyền',
              style: T.body.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '4 vai trò nhân sự · Chỉ quản trị viên được thay đổi quyền',
              style: T.small,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              OperationsGrid(
                maxColumns: 2,
                minWidth: 300,
                children: [
                  for (final role in staffRoles)
                    OperationsNotice(
                      title: staffRoleNames[role]!,
                      message: _roleDescriptions[role]!,
                      icon: Icons.shield_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _identity(AdminRecord row) => OperationsIdentity(
    name: row['name'],
    email: row['email'],
    caption: row['username'] is String
        ? 'Tên đăng nhập: ${row['username']}'
        : null,
  );
  Widget _role(AdminRecord row) => Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    child: AdminStatus(
      staffRoleNames[row['role']] ?? row['role'] as String? ?? 'Chưa xác định',
      color: row['role'] == 'ADMIN' ? T.accent : T.muted,
    ),
  );
  Widget _status(AdminRecord row) => Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    child: AdminStatus(
      row['active'] == true ? 'Đang hoạt động' : 'Đã vô hiệu hóa',
      color: row['active'] == true ? T.success : T.danger,
    ),
  );
  Widget _editButton(AdminRecord row) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      icon: const Icon(Icons.manage_accounts_outlined, size: 18),
      label: const Text('Đổi quyền'),
      onPressed: () => edit(row),
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),
  );
}
