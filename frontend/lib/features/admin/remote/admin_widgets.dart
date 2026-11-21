import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../app/account_state.dart';
import '../../../domain/staff_permissions.dart';

class AdminAsync<Value> extends StatelessWidget {
  const AdminAsync({
    super.key,
    required this.value,
    required this.reload,
    required this.builder,
  });
  final AsyncValue<Value> value;
  final VoidCallback reload;
  final Widget Function(Value) builder;
  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnRefresh: true,
    data: (data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.isLoading) const LinearProgressIndicator(),
        builder(data),
      ],
    ),
    loading: () => const Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (error, _) => StatePanel(
      title: 'Chưa tải được dữ liệu',
      message: adminError(error),
      action: AppButton('Thử tải lại', onPressed: reload),
    ),
  );
}

String adminError(Object error) => error is ApiException
    ? switch (error.code) {
        'PROMOTION_CODE_EXISTS' =>
          'Mã khuyến mãi đã tồn tại. Vui lòng nhập mã khác.',
        'PROMOTION_INVALID' =>
          'Kiểm tra giá trị giảm và thời hạn áp dụng. Ngày hết hạn phải sau ngày bắt đầu.',
        'PROMOTION_IN_USE' =>
          'Mã đã có lịch sử đơn hàng. Hãy tắt mã để ngừng áp dụng và giữ lịch sử.',
        'COLLECTION_CHANGED' =>
          'Bộ sưu tập đã thay đổi. Tải lại trước khi thao tác tiếp.',
        'DUPLICATE_COLLECTION' =>
          'Đường dẫn hoặc phong cách đã có bộ sưu tập. Chọn giá trị khác.',
        'INVALID_COLLECTION_COVER' =>
          'Ảnh bìa phải thuộc sản phẩm công khai cùng phong cách. Hãy chọn lại ảnh.',
        'TAXONOMY_SLUG_EXISTS' =>
          'Đường dẫn đã được sử dụng. Vui lòng chọn đường dẫn khác.',
        'BRAND_IN_USE' =>
          'Thương hiệu đang có sản phẩm. Chuyển sản phẩm sang thương hiệu khác trước khi xóa.',
        'CATEGORY_IN_USE' =>
          'Danh mục đang chứa sản phẩm. Chuyển sản phẩm sang danh mục khác trước khi xóa.',
        'PRODUCT_CONFLICT' =>
          'Sản phẩm hoặc biến thể đã thay đổi. Tải lại dữ liệu trước khi thao tác tiếp.',
        'PRODUCT_IN_USE' =>
          'Sản phẩm có đơn hàng, lịch sử kho, đánh giá, lượt thử đồ hoặc đang nằm trong giỏ hàng. Hãy dùng “Ẩn sản phẩm” để giữ dữ liệu liên quan.',
        'PRODUCT_SLUG_EXISTS' =>
          'Đường dẫn sản phẩm đã được sử dụng. Vui lòng chọn đường dẫn khác.',
        'SKU_EXISTS' => 'Mã SKU đã được sử dụng. Vui lòng nhập mã khác.',
        'VARIANT_EXISTS' => 'Đã có biến thể với kích cỡ và màu này.',
        'DUPLICATE_PRODUCT' =>
          'Đã có sản phẩm đang bật cùng tên và thương hiệu.',
        'INVALID_PRICE_RANGE' =>
          'Giá tối thiểu phải nhỏ hơn hoặc bằng giá tối đa.',
        'CUSTOMER_CONFLICT' =>
          'Thông tin khách hàng đã thay đổi. Tải lại dữ liệu trước khi lưu.',
        'EMAIL_ALREADY_EXISTS' =>
          'Email đã được tài khoản khác sử dụng. Vui lòng nhập email khác.',
        'USERNAME_ALREADY_EXISTS' =>
          'Tên đăng nhập đã được tài khoản khác sử dụng. Vui lòng chọn tên khác.',
        'PHONE_ALREADY_EXISTS' =>
          'Số điện thoại đã được tài khoản khác sử dụng. Vui lòng kiểm tra lại.',
        'PAYMENT_REQUIRED' =>
          'Thanh toán chưa đủ điều kiện. Kiểm tra trạng thái thu tiền trước khi giao hàng.',
        'ORDER_PAYMENT_INVALID' =>
          'Thông tin thanh toán không khớp đơn hàng. Cần kiểm tra trước khi tiếp tục.',
        'PAYMENT_RECONCILIATION_REQUIRED' =>
          'Có giao dịch đang chờ xác minh. Đối chiếu kết quả thanh toán trước khi hủy.',
        'ORDER_STATE_CONFLICT' || 'SHIPMENT_STATE_CONFLICT' =>
          'Đơn hàng đã thay đổi hoặc không thể chuyển sang trạng thái này. Tải lại để xem thông tin mới nhất.',
        'VERSION_CONFLICT' =>
          'Dữ liệu đã thay đổi hoặc số lượng không còn hợp lệ. Tải lại trước khi thao tác tiếp.',
        'INVALID_QUANTITY_RANGE' => 'Khoảng số lượng không hợp lệ.',
        'SETTLEMENT_CONFLICT' =>
          'Đơn đã có biên nhận đối soát khác. Tải lại để kiểm tra, không ghi nhận thu tiền lần nữa.',
        'AMOUNT_MISMATCH' =>
          'Số tiền đã thu phải khớp tổng thanh toán của đơn.',
        'INVALID_DATE_RANGE' =>
          'Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.',
        _ => error.message,
      }
    : 'Không đọc được dữ liệu. Vui lòng tải lại.';

class AdminHeading extends StatelessWidget {
  const AdminHeading(
    this.title,
    this.subtitle, {
    super.key,
    this.actions = const [],
  });
  final String title, subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: T
                    .display(constraints.maxWidth < 600 ? 27 : 32)
                    .copyWith(fontWeight: FontWeight.w600, letterSpacing: -.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: T.body.copyWith(color: T.muted)),
          ],
        );
        if (constraints.maxWidth >= 1000 && actions.isNotEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 24),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .4,
                ),
                child: Wrap(spacing: 10, runSpacing: 10, children: actions),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 12, children: actions),
            ],
          ],
        );
      },
    ),
  );
}

class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.panelRadius,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// Awaited mutations cannot be submitted twice. An uncertain result or version
/// conflict must be reloaded before another write, especially stock increments.
class AdminMutationDialog extends ConsumerStatefulWidget {
  const AdminMutationDialog({
    super.key,
    required this.title,
    required this.submit,
    required this.reload,
    this.fields = const [],
    this.message = '',
    this.onDisposed,
    this.submitLabel = 'Lưu thay đổi',
    this.destructive = false,
  });
  final String submitLabel;
  final bool destructive;
  final String title, message;
  final List<Widget> fields;
  final Future<void> Function() submit;
  final VoidCallback reload;
  final VoidCallback? onDisposed;
  @override
  ConsumerState<AdminMutationDialog> createState() =>
      _AdminMutationDialogState();
}

class _AdminMutationDialogState extends ConsumerState<AdminMutationDialog> {
  late final identity = ref.read(adminAccountProvider)?.id;
  final form = GlobalKey<FormState>();
  bool saving = false, needsReload = false;
  String? error;
  Future<void> save() async {
    if (saving || needsReload || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.submit();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = adminError(e);
        needsReload =
            e is! ApiException ||
            (![400, 422].contains(e.status) &&
                ![
                  'EMAIL_ALREADY_EXISTS',
                  'USERNAME_ALREADY_EXISTS',
                  'TAXONOMY_SLUG_EXISTS',
                  'DUPLICATE_COLLECTION',
                  'PROMOTION_CODE_EXISTS',
                  'PHONE_ALREADY_EXISTS',
                  'PRODUCT_SLUG_EXISTS',
                  'SKU_EXISTS',
                  'VARIANT_EXISTS',
                  'DUPLICATE_PRODUCT',
                ].contains(e.code));
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(adminAccountProvider);
    if (!isStaff(account?.role) || account?.id != identity) {
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
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(widget.message),
                    ),
                  for (final field in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: field,
                    ),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: T.body.copyWith(color: T.danger),
                      ),
                    ),
                  if (needsReload)
                    const Text(
                      'Hãy tải lại dữ liệu để kiểm tra kết quả trước khi thao tác tiếp.',
                      style: T.small,
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (needsReload)
            AppButton(
              'Tải lại dữ liệu',
              onPressed: () {
                widget.reload();
                Navigator.pop(context);
              },
            )
          else if (widget.destructive)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: T.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 18),
              label: Text(widget.submitLabel),
            )
          else
            AppButton(widget.submitLabel, busy: saving, onPressed: save),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.onDisposed?.call();
    super.dispose();
  }
}

String? requiredText(String? value, {int max = 200}) =>
    (value ?? '').trim().isEmpty
    ? 'Vui lòng nhập thông tin.'
    : value!.trim().length > max
    ? 'Tối đa $max ký tự.'
    : null;
String? priceValidation(String? value) =>
    RegExp(r'^\d{1,14}$').hasMatch(value ?? '')
    ? null
    : 'Nhập số tiền nguyên, tối đa 14 chữ số.';
