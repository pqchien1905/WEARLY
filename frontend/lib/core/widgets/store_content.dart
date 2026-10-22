import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/api_providers.dart';
import '../../app/content_provider.dart';
import '../../app/store_details.dart';
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
          data: (content) =>
              Text(content == null ? fallback : _value(content), style: style),
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

  String _value(PublishedContent content) {
    final value = switch (field) {
      'banner' => content.banner,
      'policy' => content.policy,
      _ => content.details?[field] ?? fallback,
    };
    return value.trim().isEmpty ? fallback : value;
  }
}

class StoreContactDetails extends ConsumerWidget {
  const StoreContactDetails({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteApiProvider)) return const SizedBox.shrink();
    return ref
        .watch(publishedContentProvider)
        .when(
          data: (content) {
            final details = content?.details ?? StoreDetails.fromJson(null);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final key in ['email', 'phone', 'address'])
                  if (details[key].trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(details[key]),
                    ),
              ],
            );
          },
          loading: () => const Text('Đang tải thông tin liên hệ…'),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(publishedContentProvider),
            child: const Text('Tải lại thông tin liên hệ'),
          ),
        );
  }
}
