part of 'remote_tryon_history.dart';

class _TryOnHistoryList extends StatelessWidget {
  const _TryOnHistoryList({
    required this.items,
    required this.visible,
    required this.deleting,
    required this.enabled,
    required this.onShow,
    required this.onDelete,
    required this.repo,
  });
  final List<RemoteTryOnJob> items;
  final String? visible, deleting;
  final bool enabled;
  final ValueChanged<RemoteTryOnJob> onShow, onDelete;
  final RemoteTryOnRepository repo;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final wide =
          c.maxWidth >= 1000 * MediaQuery.textScalerOf(context).scale(14) / 14;
      final rows = [
        for (final job in items)
          _TryOnHistoryRow(
            key: ValueKey(job.id),
            job: job,
            wide: wide,
            visible: visible == job.id,
            deleting: deleting == job.imageId,
            enabled: enabled,
            repo: repo,
            onShow: () => onShow(job),
            onDelete: () => onDelete(job),
          ),
      ];
      if (!wide) {
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AccountCard(child: row),
              ),
          ],
        );
      }
      return AccountCard(
        key: const ValueKey('tryon-history-table'),
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: _HistoryColumns(
                children: [
                  for (final label in [
                    'Trang phục',
                    'Kết quả',
                    'Thời gian',
                    'Thao tác',
                  ])
                    Text(
                      label,
                      style: T.small.copyWith(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            for (final row in rows) ...[
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.all(24), child: row),
            ],
          ],
        ),
      );
    },
  );
}

class _HistoryColumns extends StatelessWidget {
  const _HistoryColumns({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 4, child: children[0]),
      const SizedBox(width: 24),
      Expanded(flex: 3, child: children[1]),
      const SizedBox(width: 24),
      Expanded(flex: 3, child: children[2]),
      const SizedBox(width: 24),
      SizedBox(
        width: 216 * MediaQuery.textScalerOf(context).scale(14) / 14,
        child: children[3],
      ),
    ],
  );
}

class _TryOnHistoryRow extends StatelessWidget {
  const _TryOnHistoryRow({
    super.key,
    required this.job,
    required this.wide,
    required this.visible,
    required this.deleting,
    required this.enabled,
    required this.onShow,
    required this.onDelete,
    required this.repo,
  });
  final RemoteTryOnJob job;
  final bool wide, visible, deleting, enabled;
  final VoidCallback onShow, onDelete;
  final RemoteTryOnRepository repo;

  @override
  Widget build(BuildContext context) {
    final product = job.product;
    final category = _category(job);
    final statusColor = switch (category) {
      _HistoryFilter.ready => T.success,
      _HistoryFilter.failed => T.danger,
      _HistoryFilter.pending => T.warning,
      _ => T.muted,
    };
    final title = switch (category) {
      _HistoryFilter.ready => 'Đã tạo ảnh thử đồ',
      _HistoryFilter.pending =>
        job.status == 'pending' ? 'Đang chờ xử lý' : 'Đang tạo ảnh',
      _HistoryFilter.expired =>
        job.expiresAt.isAfter(DateTime.now())
            ? 'Ảnh không còn khả dụng'
            : 'Ảnh đã hết hạn',
      _ => 'Chưa tạo được ảnh',
    };
    final garment = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: T.radius,
          child: SizedBox(
            width: 64,
            height: 86,
            child: product?.image == null
                ? const ColoredBox(
                    color: T.canvas,
                    child: Icon(Icons.checkroom_outlined, color: T.muted),
                  )
                : FashionImage(
                    product!.image!,
                    label: '${product.name}, ảnh trang phục',
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product?.name ?? 'Trang phục không còn trong cửa hàng',
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (job.size != null || job.color != null)
                Text(
                  [
                    if (job.color != null) job.color!,
                    if (job.size != null) 'Size ${job.size}',
                  ].join(' · '),
                  style: T.small,
                ),
              Text('SKU: ${job.sku}', style: T.small),
              if (product != null)
                TextButton(
                  onPressed: enabled
                      ? () => context.go(
                          '/products/${Uri.encodeComponent(product.slug)}',
                        )
                      : null,
                  child: const Text('Xem trang phục'),
                ),
            ],
          ),
        ),
      ],
    );
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .07),
            borderRadius: T.radius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (category) {
                  _HistoryFilter.ready => Icons.check_circle_outline,
                  _HistoryFilter.pending => Icons.hourglass_top_rounded,
                  _HistoryFilter.failed => Icons.error_outline,
                  _ => Icons.timer_off_outlined,
                },
                size: 16,
                color: statusColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: T.small.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(switch (category) {
          _HistoryFilter.ready => 'Ảnh chỉ hiển thị khi bạn chọn xem.',
          _HistoryFilter.pending => 'Lịch sử tự cập nhật sau mỗi 10 giây.',
          _HistoryFilter.expired =>
            'Ảnh đã hết hạn hoặc không còn khả dụng. Bạn có thể bắt đầu lượt thử mới.',
          _ =>
            job.errorCode == null
                ? 'Lượt thử chưa hoàn tất. Bạn có thể mở phòng thử để thử lại.'
                : tryonError(job.errorCode!),
        }, style: T.small),
      ],
    );
    final time = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Đã thử', style: T.small),
        Text(_historyDate(job.createdAt), style: T.body),
        const SizedBox(height: 10),
        const Text('Ảnh được lưu đến', style: T.small),
        Text(_historyDate(job.expiresAt), style: T.body),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_canView(job))
          AppButton(
            visible ? 'Ẩn ảnh' : 'Xem ảnh thử đồ',
            outlined: true,
            icon: visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            onPressed: enabled ? onShow : null,
          ),
        if (category == _HistoryFilter.pending)
          AppButton(
            'Theo dõi yêu cầu',
            outlined: true,
            onPressed: enabled
                ? () => context.go('/virtual-try-on/${job.id}')
                : null,
          ),
        if (category != _HistoryFilter.pending &&
            product?.tryOnSupported == true)
          TextButton.icon(
            onPressed: enabled
                ? () => context.go(
                    Uri(
                      path: '/virtual-try-on',
                      queryParameters: {'product': product!.slug},
                    ).toString(),
                  )
                : null,
            icon: const Icon(Icons.checkroom_outlined, size: 18),
            label: const Text('Thử lại trang phục'),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: T.danger,
            visualDensity: VisualDensity.standard,
          ),
          onPressed: enabled ? onDelete : null,
          icon: deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline, size: 18),
          label: Text(deleting ? 'Đang xóa…' : 'Xóa ảnh và các kết quả'),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          _HistoryColumns(children: [garment, status, time, actions])
        else ...[
          garment,
          const SizedBox(height: 20),
          status,
          const Divider(height: 32),
          time,
          const SizedBox(height: 16),
          actions,
        ],
        if (visible && _canView(job)) ...[
          const Divider(height: 32),
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 18, color: T.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ảnh thử đồ riêng tư · ${product?.name ?? job.sku}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PrivateRemoteImage(
            key: ValueKey('history-image-${job.id}'),
            load: () => repo.result(job.id),
            label: 'Ảnh thử đồ riêng tư',
            downloadName: 'wearly-thu-do-${job.id}',
          ),
        ],
      ],
    );
  }
}
