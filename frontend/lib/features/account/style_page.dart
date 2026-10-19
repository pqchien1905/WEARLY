import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_details.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../core/network/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import 'account_navigation.dart';

class StylePage extends ConsumerWidget {
  const StylePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AccountFrame(
    title: 'Phong cách, theo ý bạn.',
    current: '/account/style',
    child: AccountDataView(
      freshWhileLoading: ref.watch(remoteApiProvider),
      builder: (data) => data.styleError != null
          ? StatePanel(
              title: 'Chưa mở được hồ sơ phong cách',
              message: accountError(data.styleError!),
              action: AppButton(
                'Thử lại',
                onPressed: () => ref.invalidate(accountDetailsProvider),
              ),
            )
          : _StyleEditor(
              key: ValueKey((
                ref.watch(accountProvider)?.email,
                ref.watch(remoteApiProvider)
                    ? ref.read(apiClientProvider).tokens.generation
                    : 0,
              )),
              initial: data.style,
            ),
    ),
  );
}

class _StyleEditor extends ConsumerStatefulWidget {
  const _StyleEditor({super.key, required this.initial});
  final StylePreferences initial;
  @override
  ConsumerState<_StyleEditor> createState() => _StyleEditorState();
}

class _StyleEditorState extends ConsumerState<_StyleEditor> {
  late String size = widget.initial.size,
      style = widget.initial.style,
      color = widget.initial.color;
  late int budget = widget.initial.budget;
  late int version = widget.initial.version;
  bool busy = false, saved = false;
  bool reconcile = false;
  bool reloadRequested = false;
  String? error;
  @override
  void didUpdateWidget(covariant _StyleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!busy &&
        !identical(oldWidget.initial, widget.initial) &&
        (widget.initial.version != version || reconcile || reloadRequested)) {
      size = widget.initial.size;
      style = widget.initial.style;
      color = widget.initial.color;
      budget = widget.initial.budget;
      version = widget.initial.version;
      saved = false;
      reconcile = false;
      reloadRequested = false;
      error = null;
    }
  }

  Future<void> save({bool openStylist = false}) async {
    if (busy || reconcile) return;
    setState(() {
      busy = true;
      saved = false;
      error = null;
    });
    try {
      final persisted = await ref
          .read(accountDetailsProvider.notifier)
          .saveStyle(
            StylePreferences(
              size: size,
              style: style,
              color: color,
              budget: budget,
              version: version,
            ),
          );
      if (!mounted) return;
      version = persisted.version;
      if (openStylist) {
        context.go('/ai-stylist');
      } else {
        setState(() => saved = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = accountError(e);
          reconcile =
              ref.read(remoteApiProvider) &&
              (e is! ApiException || e.status != 400);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> onChanged,
    String empty,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((label, value)),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: values
        .map(
          (v) => DropdownMenuItem(value: v, child: Text(v.isEmpty ? empty : v)),
        )
        .toList(),
    onChanged: busy || reconcile
        ? null
        : (v) => setState(() {
            onChanged(v!);
            saved = false;
          }),
  );
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 720),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DemoNotice(
          text: ref.watch(remoteApiProvider)
              ? 'Lựa chọn được lưu theo tài khoản và giữ lại khi đăng nhập lại. Chỉ dùng sở thích bạn tự chọn, không phân tích cơ thể hay suy đoán từ ảnh.'
              : 'Chỉ dùng những sở thích bạn tự chọn. Không phân tích cơ thể hay suy đoán từ ảnh. Hồ sơ được xóa khi đăng xuất hoặc tải lại trang.',
        ),
        const SizedBox(height: 28),
        Text('Bắt đầu từ điều bạn thích', style: T.display(26)),
        const SizedBox(height: 12),
        Text(
          ref.watch(remoteApiProvider)
              ? 'Ghi lại size, màu và ngân sách bạn thường chọn. Bạn có thể cập nhật bất cứ lúc nào.'
              : 'Lưu lựa chọn để áp dụng nhanh trong Stylist. Bạn vẫn có thể đổi ngân sách và size cho mỗi cuộc trò chuyện.',
        ),
        const SizedBox(height: 28),
        select(
          'Size thường chọn',
          size,
          StylePreferences.sizes,
          (v) => size = v,
          '',
        ),
        const SizedBox(height: 20),
        select(
          'Phong cách yêu thích',
          style,
          StylePreferences.styles,
          (v) => style = v,
          ref.watch(remoteApiProvider)
              ? 'Không ưu tiên phong cách'
              : 'Để Stylist gợi ý',
        ),
        const SizedBox(height: 20),
        select(
          'Màu ưu tiên',
          color,
          StylePreferences.colors,
          (v) => color = v,
          'Không giới hạn màu',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          key: ValueKey(budget),
          initialValue: budget,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Ngân sách mỗi outfit'),
          items: StylePreferences.budgets
              .map((v) => DropdownMenuItem(value: v, child: Text(money(v))))
              .toList(),
          onChanged: busy || reconcile
              ? null
              : (v) => setState(() {
                  budget = v!;
                  saved = false;
                }),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              'Lưu hồ sơ phong cách',
              busy: busy,
              onPressed: reconcile ? null : save,
            ),
            if (!ref.watch(remoteApiProvider))
              AppButton(
                'Lưu & mở Stylist',
                outlined: true,
                onPressed: busy ? null : () => save(openStylist: true),
              ),
            if (ref.watch(remoteApiProvider))
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        reloadRequested = true;
                        ref.invalidate(accountDetailsProvider);
                      },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tải lại hồ sơ'),
              ),
          ],
        ),
        if (saved || error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error ??
                    (ref.watch(remoteApiProvider)
                        ? 'Đã lưu hồ sơ phong cách.'
                        : 'Đã lưu phong cách trong phiên demo.'),
                style: TextStyle(color: error == null ? T.success : T.danger),
              ),
            ),
          ),
        if (reconcile)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Tải lại hồ sơ để kiểm tra kết quả trước khi lưu tiếp. Thay đổi chưa lưu sẽ được bỏ.',
              style: T.small,
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Size yêu thích không phải kết quả đo. Xem bảng số đo của từng sản phẩm trước khi chọn mua.',
          style: T.small,
        ),
      ],
    ),
  );
}
