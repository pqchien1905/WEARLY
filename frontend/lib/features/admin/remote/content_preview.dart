import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/account_state.dart';
import '../../../core/design/tokens.dart';
import '../../../domain/staff_permissions.dart';
import 'admin_presentation.dart';
import 'content_models.dart';

class ContentSessionDialog extends ConsumerWidget {
  const ContentSessionDialog({
    super.key,
    required this.identity,
    required this.child,
  });
  final String? identity;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(adminAccountProvider);
    if (account?.id == identity &&
        (identity == null || canStaff(account?.role, 'content.manage'))) {
      return child;
    }
    return AlertDialog(
      title: const Text('Phiên quản trị đã kết thúc'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class ContentPreview extends StatefulWidget {
  const ContentPreview({super.key, required this.values, this.full = false});
  final Map<String, String> values;
  final bool full;
  @override
  State<ContentPreview> createState() => _ContentPreviewState();
}

class _ContentPreviewState extends State<ContentPreview> {
  String section = 'banner';
  @override
  Widget build(BuildContext context) {
    final v = widget.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AdminSectionTitle('Xem trước nội dung'),
        const Text(
          'Bản xem trước văn bản. Nội dung chỉ hiển thị cho khách sau khi xuất bản.',
          style: T.small,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: section,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Vị trí hiển thị'),
          items: const [
            DropdownMenuItem(value: 'banner', child: Text('Trang chủ')),
            DropdownMenuItem(value: 'about', child: Text('Giới thiệu')),
            DropdownMenuItem(
              value: 'contact',
              child: Text('Thông tin liên hệ'),
            ),
            DropdownMenuItem(
              value: 'policy',
              child: Text('Giao hàng & đổi trả'),
            ),
            DropdownMenuItem(value: 'privacy', child: Text('Quyền riêng tư')),
            DropdownMenuItem(value: 'terms', child: Text('Điều khoản sử dụng')),
          ],
          onChanged: (s) => setState(() => section = s!),
        ),
        const SizedBox(height: 20),
        if (section == 'banner')
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: T.accent, borderRadius: T.radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v['name'] ?? '',
                  style: T.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  v['banner'] ?? '',
                  style: T.display(28).copyWith(color: Colors.white),
                  maxLines: widget.full ? null : 5,
                  overflow: widget.full ? null : TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Text(
                  v['tagline'] ?? '',
                  style: T.body.copyWith(color: Colors.white),
                ),
              ],
            ),
          )
        else if (section == 'contact')
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in contentFields.where(
                (f) => f.group == 2 && (v[f.key] ?? '').isNotEmpty,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(v[field.key]!, style: T.body),
                ),
              if ([
                'email',
                'phone',
                'address',
              ].every((key) => (v[key] ?? '').isEmpty))
                const Text(
                  'Chưa có thông tin liên hệ. Các mục trống sẽ được ẩn.',
                  style: T.small,
                ),
            ],
          )
        else
          Text(
            (v[section] ?? '').isEmpty ? 'Chưa có nội dung.' : v[section]!,
            style: T.body,
            maxLines: widget.full ? null : 12,
            overflow: widget.full ? null : TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class ContentComparison extends StatelessWidget {
  const ContentComparison({
    super.key,
    required this.draft,
    required this.published,
  });
  final Map<String, String> draft;
  final Map<String, String>? published;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (published == null)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Đây là lần xuất bản đầu tiên. Các mục bên dưới sẽ được công khai.',
          ),
        ),
      if (published != null && !contentDiffers(draft, published!))
        const Text('Nội dung giống bản đang công khai.'),
      for (final f in contentFields.where(
        (f) => published == null || draft[f.key] != published![f.key],
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                f.label,
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              if (published != null) ...[
                const SizedBox(height: 8),
                const Text('Đang công khai', style: T.small),
                SelectableText(
                  published![f.key]!.isEmpty ? '(Trống)' : published![f.key]!,
                  style: T.small,
                ),
              ],
              const SizedBox(height: 8),
              const Text('Bản chuẩn bị', style: T.small),
              SelectableText(
                draft[f.key]!.isEmpty ? '(Trống)' : draft[f.key]!,
                style: T.body,
              ),
              const Divider(height: 24),
            ],
          ),
        ),
    ],
  );
}
