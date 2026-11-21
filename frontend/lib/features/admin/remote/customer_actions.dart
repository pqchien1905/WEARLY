import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/contact_phone.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'staff_page.dart' show staffListProvider;

Future<AdminRecord?> editCustomer(
  BuildContext context,
  WidgetRef ref, {
  AdminRecord? customer,
}) async {
  final creating = customer == null;
  final name = TextEditingController(text: customer?['name']),
      email = TextEditingController(text: customer?['email']),
      phone = TextEditingController(text: customer?['phone']),
      username = TextEditingController(
        text: creating ? '' : customer['username'],
      ),
      password = TextEditingController(),
      confirmation = TextEditingController();
  var adminAccess = false, adminRole = 'MANAGER';
  final canGrantAccess = canStaff(ref.read(staffRoleProvider), 'staff.manage');
  final repo = ref.read(adminRepositoryProvider);
  AdminRecord? saved;
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: creating ? 'Thêm khách hàng mới' : 'Chỉnh sửa khách hàng',
      submitLabel: creating ? 'Tạo tài khoản' : 'Lưu thay đổi',
      message: creating
          ? 'Nhập thông tin tài khoản. Khách hàng đăng nhập bằng email; tài khoản được cấp quyền quản trị đăng nhập bằng tên đăng nhập.'
          : 'Email dùng để đăng nhập. Đổi email sẽ kết thúc các phiên hiện tại và vô hiệu mã khôi phục cũ. Thông tin giao nhận trong đơn đã đặt được giữ nguyên.',
      reload: () => refreshAdmin(ref),
      onDisposed: () {
        for (final controller in [
          name,
          email,
          phone,
          username,
          password,
          confirmation,
        ]) {
          controller.dispose();
        }
      },
      fields: [
        AppField(
          label: 'Họ và tên',
          controller: name,
          validator: (v) => requiredText(v, max: 100),
        ),
        AppField(
          label: 'Email',
          controller: email,
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            final text = (v ?? '').trim();
            return text.length > 254 ||
                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)
                ? 'Nhập địa chỉ email hợp lệ.'
                : null;
          },
        ),
        AppField(
          label: 'Số điện thoại',
          controller: phone,
          keyboardType: TextInputType.phone,
          validator: contactPhoneValidation,
        ),
        if (creating) ...[
          AppField(
            label: 'Mật khẩu',
            controller: password,
            obscure: true,
            hint: 'Từ 8 đến 128 ký tự',
            autofillHints: const [AutofillHints.newPassword],
            validator: (v) => (v ?? '').length < 8 || (v ?? '').length > 128
                ? 'Mật khẩu phải có từ 8 đến 128 ký tự.'
                : null,
          ),
          AppField(
            label: 'Nhập lại mật khẩu',
            controller: confirmation,
            obscure: true,
            validator: (v) =>
                v != password.text ? 'Mật khẩu nhập lại chưa khớp.' : null,
          ),
        ],
        StatefulBuilder(
          builder: (context, update) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Có quyền truy cập trang quản trị'),
                subtitle: !canGrantAccess
                    ? const Text('Chỉ Quản trị viên được cấp quyền này.')
                    : null,
                value: adminAccess,
                onChanged: canGrantAccess
                    ? (value) => update(() => adminAccess = value ?? false)
                    : null,
              ),
              if (adminAccess) ...[
                const SizedBox(height: 12),
                AppField(
                  label: 'Tên đăng nhập quản trị',
                  controller: username,
                  hint: '3–64 ký tự: chữ, số, dấu chấm, gạch dưới hoặc ngang',
                  validator: (v) =>
                      RegExp(
                        r'^[a-z0-9][a-z0-9_.-]{2,63}$',
                      ).hasMatch((v ?? '').trim().toLowerCase())
                      ? null
                      : 'Nhập tên đăng nhập hợp lệ, từ 3 đến 64 ký tự.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: adminRole,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vai trò quản trị',
                  ),
                  items: [
                    for (final role in staffRoles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(staffRoleNames[role]!),
                      ),
                  ],
                  onChanged: (role) {
                    if (role != null) update(() => adminRole = role);
                  },
                ),
                const SizedBox(height: 12),
                Text(switch (adminRole) {
                  'ADMIN' =>
                    'Quản trị viên: toàn quyền, bao gồm cấp và thu hồi quyền nhân sự.',
                  'WAREHOUSE' =>
                    'Kho: quản lý tồn kho, giao hàng và nhận hàng trả.',
                  'SUPPORT' => 'Hỗ trợ: xem đơn hàng và xử lý yêu cầu hỗ trợ.',
                  _ =>
                    'Quản lý: quản lý cửa hàng, không được cấp hoặc thu hồi quyền nhân sự.',
                }, style: T.small),
                const SizedBox(height: 12),
                Text(
                  'Sau khi lưu, tài khoản được quản lý tại Nhân sự & quyền và dùng để đăng nhập trang quản trị. '
                  'Mua hàng cần tài khoản khách hàng riêng. '
                  '${creating ? 'Sử dụng mật khẩu vừa nhập.' : 'Mật khẩu hiện tại được giữ nguyên; các phiên đăng nhập cũ sẽ kết thúc.'}'
                  '${customer?['active'] == false ? ' Tài khoản đang khóa sẽ vẫn bị khóa.' : ''}',
                  style: T.small,
                ),
              ],
            ],
          ),
        ),
      ],
      submit: () async {
        if (creating) {
          saved = await repo.createCustomer({
            'name': name.text.trim(),
            'email': email.text.trim().toLowerCase(),
            'phone': phone.text.trim(),
            'password': password.text,
            if (adminAccess) ...{
              'adminAccess': true,
              'adminRole': adminRole,
              'username': username.text.trim().toLowerCase(),
            },
          });
        } else {
          final changes = <String, dynamic>{
            'expectedUpdatedAt': customer['updatedAt'],
            if (adminAccess) ...{
              'adminAccess': true,
              'adminRole': adminRole,
              'username': username.text.trim().toLowerCase(),
            },
            if (name.text.trim() != customer['name']) 'name': name.text.trim(),
            if (email.text.trim().toLowerCase() != customer['email'])
              'email': email.text.trim().toLowerCase(),
            if (phone.text.trim() != customer['phone'])
              'phone': phone.text.trim(),
          };
          saved = changes.length > 1
              ? await repo.updateCustomer('${customer['id']}', changes)
              : customer;
        }
      },
    ),
  );
  if (!context.mounted || changed != true) return null;
  refreshAdmin(ref);
  if (isStaff(saved?['role'])) {
    ref.invalidate(staffListProvider);
    context.go(
      Uri(
        path: '/admin/staff',
        queryParameters: {'email': '${saved!['email']}'},
      ).toString(),
    );
    toast(context, 'Đã lưu tài khoản có quyền truy cập trang quản trị.');
    return saved;
  }
  toast(
    context,
    creating ? 'Đã thêm tài khoản khách hàng.' : 'Đã lưu thông tin khách hàng.',
  );
  return saved;
}

Future<void> toggleCustomer(
  BuildContext context,
  WidgetRef ref,
  AdminRecord customer,
) async {
  final active = customer['active'] == true;
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: active
          ? 'Khóa tài khoản khách hàng'
          : 'Mở khóa tài khoản khách hàng',
      message:
          '${customer['name']} (${customer['email']})\n\n${active ? 'Khách hàng sẽ bị đăng xuất và không thể đăng nhập hoặc đặt đơn mới. Lịch sử đơn hàng được giữ nguyên; các đơn hiện tại vẫn được xử lý.' : 'Khách hàng có thể đăng nhập lại bằng thông tin hiện tại. Phiên đã bị thu hồi sẽ không được khôi phục.'}',
      reload: () => refreshAdmin(ref),
      submit: () async {
        await repo.updateCustomer('${customer['id']}', {
          'active': !active,
          'expectedUpdatedAt': customer['updatedAt'],
        }, status: true);
      },
    ),
  );
  if (!context.mounted || changed != true) return;
  refreshAdmin(ref);
  toast(
    context,
    active
        ? 'Đã khóa tài khoản khách hàng.'
        : 'Đã mở khóa tài khoản khách hàng.',
  );
}

Future<bool> deleteCustomer(
  BuildContext context,
  WidgetRef ref,
  AdminRecord customer,
) async {
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Xóa tài khoản khách hàng?',
      submitLabel: 'Xác nhận xóa',
      destructive: true,
      message:
          'Bạn sắp xóa tài khoản ${customer['name']} (${customer['email']}).\n\n'
          'Tài khoản sẽ bị gỡ khỏi danh sách và không thể đăng nhập hoặc mở khóa lại. '
          'Lịch sử đơn hàng và thông tin liên quan được giữ lại để tra cứu, xử lý đơn và hoàn tiền. '
          'Email và số điện thoại vẫn thuộc hồ sơ đã xóa.',
      reload: () => refreshAdmin(ref),
      submit: () async {
        await repo.deleteCustomer(
          '${customer['id']}',
          '${customer['updatedAt']}',
        );
      },
    ),
  );
  if (!context.mounted || changed != true) return false;
  refreshAdmin(ref);
  toast(context, 'Đã xóa tài khoản khách hàng.');
  return true;
}
