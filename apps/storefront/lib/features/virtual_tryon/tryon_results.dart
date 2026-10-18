import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';

// Deliberately stores only garment/job metadata, never user photos or filenames.
class TryOnResult {
  const TryOnResult({required this.id, required this.slug, required this.sku});
  final String id, slug, sku;
}

final tryOnResultsProvider =
    NotifierProvider<TryOnResults, Map<String, TryOnResult>>(TryOnResults.new);

class TryOnResults extends Notifier<Map<String, TryOnResult>> {
  @override
  Map<String, TryOnResult> build() => {};
  void save(TryOnResult result) {
    final next = {...state, result.id: result};
    if (next.length > 20) next.remove(next.keys.first);
    state = next;
  }

  void remove(String id) => state = {...state}..remove(id);
  void clear() => state = {};
}

class TryOnResultPage extends ConsumerWidget {
  const TryOnResultPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(tryOnResultsProvider)[id];
    return PageBody(
      child: result == null
          ? StatePanel(
              title: 'Phiên thử đồ không còn ở đây',
              message:
                  'Kết quả demo chỉ có trong tab hiện tại. Phiên có thể đã bị xóa, hết hạn hoặc mất khi tải lại trang.',
              action: AppButton(
                'Bắt đầu thử đồ',
                onPressed: () => context.go('/virtual-try-on'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bản thử đồ của bạn.',
                  style: T.display(
                    MediaQuery.sizeOf(context).width < 600 ? 36 : 48,
                  ),
                ),
                const SizedBox(height: 24),
                const DemoNotice(
                  text:
                      'Đã hoàn tất luồng mô phỏng. Ảnh đầu vào đã được giải phóng khi rời phòng thử.',
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  color: T.soft,
                  child: Column(
                    children: [
                      const Icon(
                        Icons.checkroom_outlined,
                        size: 56,
                        color: T.accent,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Ảnh minh họa giao diện – không phải kết quả AI thực tế',
                        style: T.display(26),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Bản demo không tạo ảnh biến đổi và không xác nhận độ vừa vặn. Trang này chỉ giữ thông tin trang phục đã chọn, không giữ ảnh của bạn.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text('Biến thể: ${result.sku}', style: T.small),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => context.go('/account/try-ons'),
                      child: const Text('Lịch sử thử đồ'),
                    ),
                    AppButton(
                      'Chọn size & mua',
                      onPressed: () => context.go('/products/${result.slug}'),
                    ),
                    AppButton(
                      'Thử trang phục khác',
                      outlined: true,
                      onPressed: () => context.go('/virtual-try-on'),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(tryOnResultsProvider.notifier).remove(id),
                      child: const Text('Xóa kết quả demo'),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
    );
  }
}
