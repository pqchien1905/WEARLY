import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_tryon.dart';
import 'private_remote_image.dart';
import '../account/account_navigation.dart';
import '../account/account_components.dart';

part 'tryon_history_list.dart';

class RemoteTryOnHistory extends ConsumerStatefulWidget {
  const RemoteTryOnHistory({super.key});
  @override
  ConsumerState<RemoteTryOnHistory> createState() => _RemoteTryOnHistoryState();
}

class _RemoteTryOnHistoryState extends ConsumerState<RemoteTryOnHistory> {
  late final repo = RemoteTryOnRepository(ref.read(apiClientProvider));
  List<RemoteTryOnJob> items = [];
  String? error, visible, deleting;
  bool loading = true, loaded = false, confirming = false;
  int version = 0;
  _HistoryFilter filter = _HistoryFilter.all;
  Timer? refresh;
  bool get locked => loading || deleting != null || confirming;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    version++;
    refresh?.cancel();
    super.dispose();
  }

  void scheduleRefresh() {
    refresh?.cancel();
    final now = DateTime.now();
    final expiries =
        items
            .map((j) => j.expiresAt)
            .where((date) => date.isAfter(now))
            .toList()
          ..sort();
    Duration? delay;
    if (items.any((j) => j.pending && j.expiresAt.isAfter(now))) {
      delay = const Duration(seconds: 10);
    }
    if (expiries.isNotEmpty) {
      final untilExpiry =
          expiries.first.difference(now) + const Duration(milliseconds: 100);
      if (delay == null || untilExpiry < delay) delay = untilExpiry;
    }
    if (delay != null) refresh = Timer(delay, () => load(silent: true));
  }

  Future<void> load({bool silent = false}) async {
    if (deleting != null || confirming) return;
    refresh?.cancel();
    final current = ++version;
    setState(() {
      if (!silent) {
        loading = true;
        visible = null;
      }
      error = null;
    });
    try {
      final rows = await repo.jobs();
      if (!mounted || current != version) return;
      setState(() {
        items = rows;
        loaded = true;
        if (!items.any((j) => j.id == visible && _canView(j))) visible = null;
      });
      scheduleRefresh();
    } catch (e) {
      if (mounted && current == version) {
        setState(() {
          error = tryonError(e);
          visible = null;
        });
      }
    } finally {
      if (mounted && current == version) setState(() => loading = false);
    }
  }

  Future<void> remove(RemoteTryOnJob job) async {
    if (locked) return;
    refresh?.cancel();
    // Invalidate any background read before opening the destructive action.
    version++;
    setState(() => confirming = true);
    final count = items.where((j) => j.imageId == job.imageId).length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa ảnh và các kết quả?'),
        content: Text(
          'Ảnh gốc này đang được dùng trong $count lượt thử ở danh sách hiện tại.\n\nẢnh gốc và tất cả kết quả liên quan sẽ bị xóa, kể cả những lượt đang được lọc ẩn. Bạn không thể khôi phục sau khi xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: T.danger),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Xác nhận xóa'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (yes != true) {
      scheduleRefresh();
      return;
    }
    final current = ++version;
    setState(() {
      deleting = job.imageId;
      visible = null;
      error = null;
    });
    try {
      await repo.deleteImage(job.imageId);
      if (!mounted || current != version) return;
      setState(() => items.removeWhere((row) => row.imageId == job.imageId));
      toast(context, 'Đã xóa ảnh gốc và các kết quả liên quan.');
    } catch (e) {
      if (mounted && current == version) {
        setState(
          () => error =
              'Chưa xác nhận được việc xóa ảnh. Làm mới lịch sử để kiểm tra. ${tryonError(e)}',
        );
      }
    } finally {
      if (mounted && current == version) {
        setState(() => deleting = null);
        if (error == null) scheduleRefresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = items
        .where((j) => filter == _HistoryFilter.all || _category(j) == filter)
        .toList();
    return AccountFrame(
      title: 'Lịch sử thử đồ',
      current: '/account/try-ons',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountToolbar(
            label: loaded
                ? '${items.length} lượt thử đồ · Mới nhất trước'
                : loading
                ? 'Đang tải lịch sử…'
                : 'Chưa tải được lịch sử',
            actions: [
              AppButton(
                'Đến phòng thử',
                icon: Icons.checkroom_outlined,
                onPressed: deleting != null || confirming
                    ? null
                    : () => context.go('/virtual-try-on'),
              ),
              TextButton.icon(
                onPressed: locked ? null : load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Làm mới lịch sử'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const AccountNotice(
            icon: Icons.privacy_tip_outlined,
            text:
                'Ảnh riêng tư được lưu tối đa 24 giờ. Chỉ mở ảnh khi bạn chọn xem. Xóa ảnh gốc sẽ xóa cả các kết quả liên quan. Ảnh AI không đảm bảo độ vừa vặn.',
          ),
          const SizedBox(height: 24),
          if (loaded && items.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in _HistoryFilter.values)
                  ChoiceChip(
                    label: Text(
                      '${value.label} (${value == _HistoryFilter.all ? items.length : items.where((j) => _category(j) == value).length})',
                    ),
                    selected: filter == value,
                    onSelected: locked
                        ? null
                        : (_) => setState(() {
                            filter = value;
                            visible = null;
                          }),
                    visualDensity: VisualDensity.standard,
                    selectedColor: T.soft,
                    backgroundColor: T.surface,
                    labelStyle: T.small.copyWith(
                      color: filter == value ? T.accent : T.ink,
                    ),
                    side: BorderSide(
                      color: filter == value ? T.accent : T.controlLine,
                    ),
                    shape: const RoundedRectangleBorder(borderRadius: T.radius),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Tối đa 20 lượt gần nhất trong 24 giờ. Thời gian hiển thị theo giờ Việt Nam (GMT+7).',
              style: T.small,
            ),
            const SizedBox(height: 20),
          ],
          if (loading) const AccountLoading(label: 'Đang tải lịch sử thử đồ…'),
          if (!loading && error != null) ...[
            AccountCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      loaded
                          ? 'Chưa cập nhật được lịch sử'
                          : 'Chưa tải được lịch sử thử đồ',
                      style: T.body.copyWith(
                        color: T.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(error!, style: T.body),
                  if (loaded)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Danh sách bên dưới là dữ liệu đã tải trước đó.',
                        style: T.small,
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppButton(
                    'Thử lại',
                    outlined: true,
                    onPressed: locked ? null : load,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (!loading && loaded && items.isEmpty && error == null)
            const AccountEmptyState(
              title: 'Góc thử đồ đang chờ bạn',
              message: 'Bạn chưa có yêu cầu thử đồ còn trong thời gian lưu.',
              icon: Icons.checkroom_outlined,
            ),
          if (!loading && items.isNotEmpty && shown.isEmpty)
            AccountEmptyState(
              title: 'Chưa có lượt thử ở trạng thái này',
              message: 'Chọn trạng thái khác hoặc xem tất cả lịch sử thử đồ.',
              icon: Icons.filter_alt_off_outlined,
              action: AppButton(
                'Xem tất cả',
                outlined: true,
                onPressed: () => setState(() => filter = _HistoryFilter.all),
              ),
            ),
          if (!loading && shown.isNotEmpty)
            _TryOnHistoryList(
              items: shown,
              visible: visible,
              deleting: deleting,
              enabled: !locked,
              onShow: (job) =>
                  setState(() => visible = visible == job.id ? null : job.id),
              onDelete: remove,
              repo: repo,
            ),
        ],
      ),
    );
  }
}

enum _HistoryFilter {
  all('Tất cả'),
  ready('Có ảnh'),
  pending('Đang xử lý'),
  failed('Chưa thành công'),
  expired('Không còn ảnh');

  const _HistoryFilter(this.label);
  final String label;
}

bool _canView(RemoteTryOnJob job) =>
    job.resultAvailable && job.expiresAt.isAfter(DateTime.now());
_HistoryFilter _category(RemoteTryOnJob job) {
  if (!job.expiresAt.isAfter(DateTime.now()) ||
      job.status == 'completed' && !job.resultAvailable) {
    return _HistoryFilter.expired;
  }
  if (job.pending) return _HistoryFilter.pending;
  return _canView(job) ? _HistoryFilter.ready : _HistoryFilter.failed;
}

String _historyDate(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 7));
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
