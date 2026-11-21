part of 'orders_page.dart';

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key, this.id});
  final String? id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(accountProvider);
    return _OrdersView(key: ValueKey((user?.id, user?.email)), id: id);
  }
}

class _OrdersView extends ConsumerStatefulWidget {
  const _OrdersView({super.key, this.id});
  final String? id;
  @override
  ConsumerState<_OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends ConsumerState<_OrdersView> {
  final search = TextEditingController();
  String status = '';
  bool loadingMore = false;

  @override
  void initState() {
    super.initState();
    scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant _OrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) scheduleRefresh();
  }

  void scheduleRefresh() => Future.microtask(() {
    if (mounted) refresh();
  });

  void refresh() {
    final store = ref.read(commerceProvider);
    if (!store.remote) return;
    if (widget.id != null) {
      store.loadOrder(widget.id!);
    } else if (store.historyState.pending == 0) {
      setState(() => loadingMore = false);
      store.refreshOrders();
    }
  }

  void more() {
    final store = ref.read(commerceProvider);
    if (store.historyState.pending > 0) return;
    setState(() => loadingMore = true);
    store.loadMoreOrders();
  }

  void clearFilters() => setState(() {
    search.clear();
    status = '';
  });

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(commerceProvider);
    final detail = widget.id != null;
    final load = detail ? store.detailState(widget.id!) : store.historyState;
    final selected = store.orders.where((o) => o.id == widget.id).firstOrNull;
    final missing =
        detail &&
        load.error is ApiException &&
        [400, 404].contains((load.error as ApiException).status);
    final stale = load.loaded && load.error != null;
    final waiting = load.pending > 0;
    final orders = store.orderHistory;
    final filtered =
        orders
            .where(
              (o) =>
                  (status.isEmpty || o.status == status) &&
                  orderMatches(o, search.text),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    Widget initialFeedback() => load.loading
        ? const AccountLoading(label: 'Đang tải đơn hàng…')
        : AccountEmptyState(
            title: detail
                ? 'Chưa tải được chi tiết đơn'
                : 'Chưa tải được đơn hàng',
            message: load.error == null
                ? 'Chưa có dữ liệu đơn hàng. Hãy thử tải lại.'
                : accountError(load.error!),
            icon: Icons.cloud_off_outlined,
            action: AppButton('Thử tải lại', onPressed: refresh),
          );

    return AccountFrame(
      title: detail ? 'Chi tiết đơn hàng' : 'Đơn hàng của bạn.',
      current: '/account/orders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!store.remote) ...[
            const AccountNotice(
              text:
                  'Đơn hàng mô phỏng – chưa thanh toán thật. Lịch sử của tab hiện tại, không phải dữ liệu tài khoản đã xác thực. Tải lại trang sẽ xóa đơn.',
            ),
            const SizedBox(height: 24),
          ],
          if (detail) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => context.go('/account/orders'),
                  icon: const Icon(Icons.west, size: 18),
                  label: const Text('Về danh sách đơn'),
                ),
                if (store.remote)
                  TextButton.icon(
                    onPressed: waiting ? null : refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Cập nhật đơn hàng'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (missing || (!store.remote && selected == null))
              AccountEmptyState(
                title: 'Không tìm thấy đơn hàng',
                message: store.remote
                    ? 'Đơn hàng không tồn tại hoặc không thuộc tài khoản của bạn.'
                    : 'Mã đơn không có trong tab này hoặc dữ liệu đã mất khi tải lại trang.',
                icon: Icons.receipt_long_outlined,
                action: AppButton(
                  'Xem lịch sử đơn hàng',
                  onPressed: () => context.go('/account/orders'),
                ),
              )
            else if (!load.loaded || selected == null)
              initialFeedback()
            else ...[
              if (stale)
                _OrderLoadNotice(
                  message:
                      'Chưa cập nhật được đơn hàng. Đang hiển thị thông tin lần tải trước. ${accountError(load.error!)}',
                  retry: refresh,
                ),
              if (waiting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Đang cập nhật đơn hàng',
                  ),
                ),
              _OrderDetail(
                order: selected,
                remote: store.remote,
                actionsEnabled: !waiting && !stale,
              ),
            ],
          ] else if (!load.loaded)
            initialFeedback()
          else ...[
            AccountToolbar(
              label: store.hasMoreOrders
                  ? '${orders.length} / ${store.totalOrders} đơn đã tải'
                  : '${orders.length} đơn hàng',
              actions: [
                if (search.text.isNotEmpty || status.isNotEmpty)
                  TextButton(
                    onPressed: clearFilters,
                    child: const Text('Xóa bộ lọc'),
                  ),
                if (store.remote)
                  TextButton.icon(
                    onPressed: waiting ? null : refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Cập nhật đơn hàng'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _OrderFilters(
              search: search,
              status: status,
              orders: orders,
              remote: store.remote,
              partial: store.hasMoreOrders,
              onChanged: () => setState(() {}),
              onStatus: (v) {
                FocusScope.of(context).unfocus();
                setState(() => status = v);
              },
            ),
            const SizedBox(height: 20),
            if (stale)
              _OrderLoadNotice(
                message:
                    '${loadingMore ? 'Chưa tải thêm được đơn hàng.' : 'Chưa cập nhật được danh sách.'} Các đơn bên dưới là dữ liệu lần tải trước. ${accountError(load.error!)}',
                retry: loadingMore ? more : refresh,
              ),
            if (waiting)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Đang cập nhật danh sách đơn hàng',
                ),
              ),
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${filtered.length} kết quả · Mới nhất trước · Giờ Việt Nam (GMT+7)',
                  style: T.small,
                ),
              ),
            ),
            if (filtered.isEmpty)
              AccountEmptyState(
                title: orders.isEmpty
                    ? 'Bạn chưa có đơn hàng'
                    : 'Không có đơn phù hợp',
                icon: Icons.shopping_bag_outlined,
                message: orders.isEmpty
                    ? 'Đơn bạn đặt sẽ xuất hiện tại đây.'
                    : store.hasMoreOrders
                    ? 'Chưa thấy kết quả trong các đơn đã tải. Bạn có thể tải thêm đơn cũ hoặc bỏ bộ lọc.'
                    : 'Thử mã đơn, tên sản phẩm khác hoặc bỏ bộ lọc trạng thái.',
                action: AppButton(
                  orders.isEmpty ? 'Khám phá cửa hàng' : 'Bỏ bộ lọc',
                  onPressed: orders.isEmpty
                      ? () => context.go('/shop')
                      : clearFilters,
                ),
              )
            else
              _OrderList(orders: filtered),
            if (store.hasMoreOrders)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: waiting ? null : more,
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      waiting && loadingMore
                          ? 'Đang tải thêm…'
                          : 'Tải thêm đơn hàng',
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
