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
import 'account_components.dart';

part 'style_choices.dart';

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
  late StylePreferences baseline = widget.initial;
  late String size = baseline.size,
      style = baseline.style,
      color = baseline.color;
  late int budget = baseline.budget;
  bool busy = false, saved = false, reconcile = false, confirming = false;
  bool reloadRequested = false;
  String? error;
  bool get dirty =>
      size != baseline.size ||
      style != baseline.style ||
      color != baseline.color ||
      budget != baseline.budget;
  bool get locked => busy || reconcile || confirming;

  void restore(StylePreferences value) {
    baseline = value;
    size = value.size;
    style = value.style;
    color = value.color;
    budget = value.budget;
    saved = false;
    reconcile = false;
    reloadRequested = false;
    error = null;
  }

  @override
  void didUpdateWidget(covariant _StyleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!busy &&
        !identical(oldWidget.initial, widget.initial) &&
        (reloadRequested || widget.initial.version != baseline.version)) {
      if (dirty && !reloadRequested) {
        reconcile = true;
        error =
            'Hồ sơ đã thay đổi ở nơi khác. Tải lại để xem lựa chọn mới nhất.';
      } else {
        restore(widget.initial);
      }
    }
  }

  void change(VoidCallback update) {
    if (locked) return;
    setState(() {
      update();
      saved = false;
      error = null;
    });
  }

  Future<void> reload() async {
    if (busy || confirming) return;
    if (dirty && !reconcile) {
      setState(() => confirming = true);
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Tải lại hồ sơ?'),
          content: const Text(
            'Bạn có thay đổi chưa lưu. Tải lại sẽ thay thế các lựa chọn này bằng hồ sơ đã lưu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Tiếp tục chỉnh sửa'),
            ),
            AppButton(
              'Bỏ thay đổi và tải lại',
              onPressed: () => Navigator.pop(c, true),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => confirming = false);
      if (discard != true) return;
    }
    reloadRequested = true;
    ref.invalidate(accountDetailsProvider);
  }

  Future<void> save({bool openStylist = false}) async {
    if (locked) return;
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
              version: baseline.version,
            ),
          );
      if (!mounted) return;
      setState(() {
        restore(persisted);
        saved = true;
      });
      if (openStylist) context.go('/ai-stylist');
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

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    return AccountCard(
      title: 'Bắt đầu từ điều bạn thích',
      description:
          'Chọn những gì khiến bạn thấy thoải mái và tự tin. Mỗi mục chọn một lựa chọn; bạn có thể đổi bất cứ lúc nào.',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountGrid(
            minColumnWidth: 340,
            children: [
              _StyleSection(
                key: const ValueKey('style-size-section'),
                number: '01',
                title: 'Size thường chọn',
                description: 'Kích cỡ bạn thường mặc hằng ngày.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final value in StylePreferences.sizes)
                          _StyleChoice(
                            label: value,
                            group: 'Size thường chọn',
                            selected: size == value,
                            onPressed: locked
                                ? null
                                : () => change(() => size = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Mỗi thiết kế có độ vừa vặn khác nhau. Hãy đối chiếu số đo trên trang sản phẩm trước khi chọn mua.',
                      style: T.small,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.straighten_outlined, size: 18),
                      label: const Text('Cách chọn size phù hợp'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Chọn size vừa với bạn'),
                          content: const Text(
                            'Đo vòng ngực, eo và hông bằng thước dây, sau đó đối chiếu với bảng số đo của từng sản phẩm.\n\nSize trong hồ sơ là sở thích của bạn, không phải kết quả đo cơ thể. Ảnh thử đồ không xác nhận độ vừa vặn.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Đã hiểu'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _StyleSection(
                key: const ValueKey('style-preference-section'),
                number: '02',
                title: 'Phong cách yêu thích',
                description: 'Một điểm bắt đầu cho gu ăn mặc của bạn.',
                child: _StyleOptions(
                  children: [
                    for (final value in StylePreferences.styles)
                      _StyleChoice(
                        label: value.isEmpty ? 'Linh hoạt' : value,
                        group: 'Phong cách yêu thích',
                        description: switch (value) {
                          'Tối giản' => 'Gọn gàng, dễ phối',
                          'Thanh lịch' => 'Chỉn chu, tinh tế',
                          'Thư giãn' => 'Thoải mái, tự nhiên',
                          _ => 'Không ưu tiên cố định',
                        },
                        icon: switch (value) {
                          'Tối giản' => Icons.crop_square_rounded,
                          'Thanh lịch' => Icons.diamond_outlined,
                          'Thư giãn' => Icons.wb_sunny_outlined,
                          _ => Icons.auto_awesome_outlined,
                        },
                        selected: style == value,
                        onPressed: locked
                            ? null
                            : () => change(() => style = value),
                      ),
                  ],
                ),
              ),
              _StyleSection(
                number: '03',
                title: 'Màu ưu tiên',
                description: 'Chọn tông màu bạn hay tìm đến nhất.',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in StylePreferences.colors)
                      _StyleChoice(
                        label: value.isEmpty ? 'Không giới hạn màu' : value,
                        group: 'Màu ưu tiên',
                        swatch: _styleColors[value],
                        icon: value.isEmpty ? Icons.palette_outlined : null,
                        selected: color == value,
                        onPressed: locked
                            ? null
                            : () => change(() => color = value),
                      ),
                  ],
                ),
              ),
              _StyleSection(
                number: '04',
                title: 'Ngân sách mỗi outfit',
                description: 'Mức bạn dự định chi cho một bộ trang phục.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final value in StylePreferences.budgets) ...[
                      if (value != StylePreferences.budgets.first)
                        const SizedBox(height: 8),
                      _StyleChoice(
                        label: money(value),
                        group: 'Ngân sách mỗi outfit',
                        selected: budget == value,
                        onPressed: locked
                            ? null
                            : () => change(() => budget = value),
                        trailingCheck: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Container(
            key: const ValueKey('style-summary'),
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: T.canvas,
              borderRadius: T.radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lựa chọn của bạn',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Size $size · ${style.isEmpty ? 'Phong cách linh hoạt' : style} · ${color.isEmpty ? 'Không giới hạn màu' : 'Màu $color'} · ${money(budget)} / bộ',
                  style: T.body.copyWith(color: T.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 40),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  error != null
                      ? Icons.error_outline
                      : saved
                      ? Icons.check_circle_outline
                      : dirty
                      ? Icons.edit_outlined
                      : Icons.check_circle_outline,
                  size: 18,
                  color: error != null
                      ? T.danger
                      : saved
                      ? T.success
                      : T.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error ??
                        (busy
                            ? 'Đang lưu hồ sơ…'
                            : saved
                            ? remote
                                  ? 'Đã lưu hồ sơ phong cách.'
                                  : 'Đã lưu phong cách trong phiên demo.'
                            : dirty
                            ? 'Bạn có thay đổi chưa lưu.'
                            : remote && baseline.version > 0
                            ? 'Đang hiển thị hồ sơ đã lưu.'
                            : 'Chọn sở thích rồi lưu hồ sơ của bạn.'),
                    style: T.small.copyWith(
                      color: error != null
                          ? T.danger
                          : saved
                          ? T.success
                          : T.muted,
                    ),
                  ),
                ),
              ],
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                'Lưu hồ sơ phong cách',
                busy: busy,
                icon: Icons.check,
                onPressed: locked ? null : save,
              ),
              TextButton.icon(
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Hoàn tác thay đổi'),
                onPressed: !dirty || locked
                    ? null
                    : () => setState(() => restore(baseline)),
              ),
              if (remote)
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tải lại hồ sơ'),
                  onPressed: busy || confirming ? null : reload,
                ),
              if (!remote)
                AppButton(
                  'Lưu & mở Stylist',
                  outlined: true,
                  onPressed: locked ? null : () => save(openStylist: true),
                ),
            ],
          ),
          const SizedBox(height: 24),
          AccountNotice(
            icon: Icons.verified_user_outlined,
            text: remote
                ? 'Sở thích được lưu theo tài khoản và giữ lại khi đăng nhập lại. Chỉ sử dụng lựa chọn bạn cung cấp, không phân tích cơ thể hay suy đoán từ ảnh.'
                : 'Chỉ dùng những sở thích bạn tự chọn. Không phân tích cơ thể hay suy đoán từ ảnh. Hồ sơ được xóa khi đăng xuất hoặc tải lại trang.',
          ),
        ],
      ),
    );
  }
}
