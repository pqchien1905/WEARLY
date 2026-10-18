import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/review_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';

class ReviewEditor extends ConsumerStatefulWidget {
  const ReviewEditor({
    super.key,
    required this.productId,
    required this.repository,
    this.previous,
    this.deleting = false,
  });
  final String productId;
  final OwnerReviewRepository repository;
  final ProductReview? previous;
  final bool deleting;
  @override
  ConsumerState<ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends ConsumerState<ReviewEditor> {
  final form = GlobalKey<FormState>();
  late final comment = TextEditingController(
    text: widget.previous?.comment ?? '',
  );
  late int rating = widget.previous?.rating ?? 0;
  late final identity = ref.read(accountProvider)?.id;
  bool busy = false, reconcile = false;
  String? error;
  Future<void> submit() async {
    if (busy || reconcile) return;
    if (!widget.deleting && (!form.currentState!.validate() || rating == 0)) {
      setState(() => error = rating == 0 ? 'Hãy chọn số sao.' : null);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.deleting) {
        await widget.repository.remove(widget.productId, widget.previous!);
      } else {
        await widget.repository.save(
          widget.productId,
          rating: rating,
          comment: comment.text,
          previous: widget.previous,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e is ApiException
            ? e.message
            : 'Chưa xác định được kết quả. Hãy kiểm tra lại.';
        reconcile = e is! ApiException || e.status != 400;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    if (account == null ||
        account.id != identity ||
        ref.read(apiClientProvider).tokens.generation !=
            widget.repository.generation) {
      return AlertDialog(
        title: const Text('Phiên khách hàng đã kết thúc'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      );
    }
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          widget.deleting
              ? 'Xóa đánh giá?'
              : widget.previous == null
              ? 'Chia sẻ trải nghiệm của bạn'
              : 'Sửa đánh giá của bạn',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.deleting)
                    const Text(
                      'Đánh giá sẽ được gỡ khỏi sản phẩm. Bạn vẫn có thể viết lại sau.',
                    )
                  else ...[
                    const Text(
                      'Trải nghiệm của bạn với sản phẩm',
                      style: T.body,
                    ),
                    Wrap(
                      children: [
                        for (var value = 1; value <= 5; value++)
                          IconButton(
                            tooltip: 'Chọn $value sao',
                            isSelected: rating == value,
                            onPressed: busy || reconcile
                                ? null
                                : () => setState(() => rating = value),
                            icon: Icon(
                              value <= rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: T.accent,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: comment,
                      enabled: !busy && !reconcile,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => Text('${comment.text.runes.length} / 2000'),
                      decoration: const InputDecoration(
                        labelText: 'Nội dung đánh giá',
                        hintText: 'Chất liệu, độ vừa vặn, cảm giác khi mặc…',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Hãy viết nội dung đánh giá.'
                          : value!.trim().runes.length > 2000
                          ? 'Tối đa 2000 ký tự.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Đánh giá được công khai. Không ghi thông tin liên hệ cá nhân.',
                      style: T.small,
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: T.body.copyWith(color: T.danger),
                      ),
                    ),
                  if (reconcile)
                    const Text(
                      'Kiểm tra lại dữ liệu trước khi thực hiện thao tác tiếp.',
                      style: T.small,
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (reconcile)
            AppButton(
              'Kiểm tra lại',
              onPressed: () {
                ref
                    .read(reviewRevisionProvider.notifier)
                    .refresh(widget.productId);
                Navigator.pop(context);
              },
            )
          else
            AppButton(
              widget.deleting
                  ? 'Xóa đánh giá'
                  : widget.previous == null
                  ? 'Gửi đánh giá'
                  : 'Lưu đánh giá',
              busy: busy,
              onPressed: submit,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }
}
