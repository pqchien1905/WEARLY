import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/api_providers.dart';
import '../../../core/widgets/primitives.dart';

class NewsletterUnsubscribePage extends ConsumerStatefulWidget {
  const NewsletterUnsubscribePage({super.key, required this.token});
  final String? token;
  @override
  ConsumerState<NewsletterUnsubscribePage> createState() =>
      _NewsletterUnsubscribePageState();
}

class _NewsletterUnsubscribePageState
    extends ConsumerState<NewsletterUnsubscribePage> {
  bool busy = false, done = false;
  String? error;
  Future<void> unsubscribe() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .request(
            'POST',
            'content/newsletter/unsubscribe',
            body: {'token': widget.token},
            authenticated: false,
          );
      if (mounted) setState(() => done = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hủy đăng ký nhận tin',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            Text(
              done
                  ? 'Đã ghi nhận yêu cầu. Bạn sẽ không nhận các bản tin tiếp theo.'
                  : widget.token == null
                  ? 'Đường dẫn không hợp lệ. Hãy mở đường dẫn hủy đăng ký trong email.'
                  : 'Xác nhận ngừng nhận bản tin Wearly. Email về đơn hàng và hỗ trợ vẫn được gửi khi cần.',
            ),
            if (error != null) Text(error!),
            const SizedBox(height: 20),
            if (!done && widget.token != null)
              AppButton(
                'Ngừng nhận bản tin',
                busy: busy,
                onPressed: busy ? null : unsubscribe,
              ),
          ],
        ),
      ),
    ),
  );
}
