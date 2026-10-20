import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/api_providers.dart';
import '../../app/content_provider.dart';
import 'primitives.dart';

/// Only the public publication contract is used on storefront surfaces.
class StoreContentText extends ConsumerWidget {
  const StoreContentText({
    super.key,
    required this.field,
    required this.fallback,
    this.style,
  });
  final String field, fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteApiProvider)) return Text(fallback, style: style);
    return ref
        .watch(publishedContentProvider)
        .when(
          data: (content) => Text(
            content == null
                ? fallback
                : (field == 'banner' ? content.banner : content.policy),
            style: style,
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => StatePanel(
            title: 'Chưa tải được nội dung cửa hàng',
            message: 'Vui lòng thử lại để xem nội dung đã xuất bản.',
            action: AppButton(
              'Tải lại nội dung',
              onPressed: () => ref.invalidate(publishedContentProvider),
            ),
          ),
        );
  }
}
