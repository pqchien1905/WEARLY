import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/account_state.dart';
import '../../../app/api_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

final staffListProvider = FutureProvider.autoDispose
    .family<AdminPage, ({String email, int page})>(
      (ref, key) => ref
          .watch(adminRepositoryProvider)
          .staff(email: key.email, page: key.page),
    );

class RemoteStaffPage extends ConsumerStatefulWidget {
  const RemoteStaffPage({super.key});
  @override
  ConsumerState<RemoteStaffPage> createState() => _RemoteStaffPageState();
}

class _RemoteStaffPageState extends ConsumerState<RemoteStaffPage> {
  final email = TextEditingController(), form = GlobalKey<FormState>();
  String query = '';
  int page = 1;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  void reload() => ref.invalidate(staffListProvider);
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
          StatefulBuilder(
            builder: (context, update) => Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: role,
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
    final provider = staffListProvider((email: query, page: page));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminHeading(
          'Nhân sự & quyền truy cập',
          'Tìm tài khoản đã đăng ký bằng email để cấp quyền. Chỉ quản trị viên được thay đổi phân quyền.',
        ),
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email tài khoản'),
                maxLength: 254,
                validator: (v) =>
                    RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch((v ?? '').trim())
                    ? null
                    : 'Nhập email hợp lệ.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  AppButton(
                    'Tìm tài khoản',
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        setState(() {
                          query = email.text.trim().toLowerCase();
                          page = 1;
                        });
                      }
                    },
                  ),
                  AppButton(
                    'Hiển thị nhân sự',
                    outlined: true,
                    onPressed: () {
                      email.clear();
                      setState(() {
                        query = '';
                        page = 1;
                      });
                      reload();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AdminAsync(
          value: ref.watch(provider),
          reload: reload,
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.items.isEmpty)
                const Text('Không tìm thấy tài khoản.', style: T.body),
              for (final row in data.items)
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row['name'], style: T.body),
                      SelectableText(row['email'], style: T.body),
                      Text(
                        '${staffRoleNames[row['role']] ?? row['role']} · ${row['active'] == true ? 'Đang hoạt động' : 'Đã vô hiệu hóa'}',
                        style: T.small,
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        'Đổi quyền',
                        outlined: true,
                        onPressed: () => edit(row),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  AppButton(
                    'Trang trước',
                    outlined: true,
                    onPressed: page > 1 ? () => setState(() => page--) : null,
                  ),
                  Text('Trang $page · ${data.total} tài khoản'),
                  AppButton(
                    'Trang sau',
                    outlined: true,
                    onPressed: data.hasNext
                        ? () => setState(() => page++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
