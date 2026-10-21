import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_tryon.dart';
import 'private_remote_image.dart';

class RemoteTryOnHistory extends ConsumerStatefulWidget {
  const RemoteTryOnHistory({super.key});
  @override
  ConsumerState<RemoteTryOnHistory> createState() => _RemoteTryOnHistoryState();
}

class _RemoteTryOnHistoryState extends ConsumerState<RemoteTryOnHistory> {
  late final repo = RemoteTryOnRepository(ref.read(apiClientProvider));
  List<RemoteTryOnJob> items = [];
  String? error, visible, deleting;
  bool loading = true;
  int version = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    version++;
    super.dispose();
  }

  Future<void> load() async {
    final current = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await repo.jobs();
      if (mounted && current == version) setState(() => items = rows);
    } catch (e) {
      if (mounted && current == version) setState(() => error = tryonError(e));
    } finally {
      if (mounted && current == version) setState(() => loading = false);
    }
  }

  Future<void> remove(RemoteTryOnJob job) async {
    if (deleting != null || loading) return;
    final current = ++version;
    setState(() {
      deleting = job.imageId;
      visible = null;
      error = null;
    });
    try {
      await repo.deleteImage(job.imageId);
      if (mounted && current == version) {
        setState(() => items.removeWhere((row) => row.imageId == job.imageId));
      }
    } catch (e) {
      if (mounted && current == version) {
        setState(() => error = 'Chưa xóa được ảnh. ${tryonError(e)}');
      }
    } finally {
      if (mounted && current == version) setState(() => deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lịch sử thử đồ', style: T.display(36)),
        const SizedBox(height: 12),
        const Text(
          'Ảnh riêng tư được lưu tối đa 24 giờ. Xóa ảnh gốc sẽ xóa cả các kết quả liên quan. Ảnh AI chỉ mô phỏng vẻ ngoài, không đảm bảo độ vừa vặn.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              'Đến phòng thử',
              onPressed: () => context.go('/virtual-try-on'),
            ),
            AppButton(
              'Làm mới lịch sử',
              outlined: true,
              onPressed: loading || deleting != null ? null : load,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(error!),
          ),
        if (!loading && error == null && items.isEmpty)
          const Text('Bạn chưa có yêu cầu thử đồ còn trong thời gian lưu.'),
        for (final job in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Trang phục ${job.sku}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('${_status(job)} · ${_date(job.createdAt.toLocal())}'),
                Text(
                  'Chi phí dịch vụ ước tính: ${money(job.estimatedCost)}; không cộng vào đơn hàng.',
                  style: T.small,
                ),
                Text(
                  'Thời hạn ảnh: ${_date(job.expiresAt.toLocal())}',
                  style: T.small,
                ),
                if (job.errorCode != null) Text(tryonError(job.errorCode!)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (job.resultAvailable)
                      AppButton(
                        visible == job.id ? 'Ẩn ảnh' : 'Xem ảnh thử đồ',
                        outlined: true,
                        onPressed: deleting != null
                            ? null
                            : () => setState(
                                () =>
                                    visible = visible == job.id ? null : job.id,
                              ),
                      ),
                    if (job.pending)
                      AppButton(
                        'Theo dõi yêu cầu',
                        outlined: true,
                        onPressed: () =>
                            context.go('/virtual-try-on/${job.id}'),
                      ),
                    AppButton(
                      'Xóa ảnh và các kết quả',
                      outlined: true,
                      busy: deleting == job.imageId,
                      onPressed: loading || deleting != null
                          ? null
                          : () => remove(job),
                    ),
                  ],
                ),
                if (visible == job.id)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: PrivateRemoteImage(
                      key: ValueKey(job.id),
                      load: () => repo.result(job.id),
                      label: 'Ảnh thử đồ riêng tư',
                    ),
                  ),
                const SizedBox(height: 16),
                const Divider(),
              ],
            ),
          ),
      ],
    ),
  );
  String _status(RemoteTryOnJob job) => job.resultAvailable
      ? 'Đã tạo ảnh thử đồ'
      : job.pending
      ? 'Đang xử lý'
      : 'Yêu cầu đã kết thúc';
  String _date(DateTime date) =>
      '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
