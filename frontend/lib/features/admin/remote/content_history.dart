import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import 'admin_widgets.dart';
import 'admin_providers.dart';
import 'inventory_widgets.dart' show InventoryPager;
import 'order_presentation.dart' show adminOrderDate;

class ContentHistory extends ConsumerStatefulWidget {
  const ContentHistory({super.key});
  @override
  ConsumerState<ContentHistory> createState() => _ContentHistoryState();
}

class _ContentHistoryState extends ConsumerState<ContentHistory> {
  int page = 1;
  @override
  Widget build(BuildContext context) => AdminAsync(
    value: ref.watch(adminContentHistoryProvider(page)),
    reload: () => ref.invalidate(adminContentHistoryProvider(page)),
    builder: (result) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Chưa có thao tác lưu hoặc xuất bản.'),
          ),
        for (final row in result.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (row['action']) {
                  'CONTENT_PUBLISHED' => 'Xuất bản nội dung',
                  'CONTENT_DRAFT_RESTORED' => 'Khôi phục bản nháp',
                  _ => 'Lưu bản nháp',
                }, style: T.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  '${adminOrderDate(row['createdAt'])} (UTC+7) · Phiên bản ${row['details']?['after']?['version'] ?? '—'}',
                  style: T.small,
                ),
                const SizedBox(height: 4),
                Text('Người thao tác: ${row['actorId']}', style: T.small),
                const Divider(height: 20),
              ],
            ),
          ),
        InventoryPager(page: result, go: (p) => setState(() => page = p)),
      ],
    ),
  );
}
