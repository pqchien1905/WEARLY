import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_presentation.dart';
import 'admin_column_row.dart';
import 'order_presentation.dart' show adminOrderDate;

const _collectionColumnWidths = <double>[240, 85, 48, 126, 90, 96, 244];
bool _collectionColumns(BuildContext context, double width) =>
    width >= 1050 && MediaQuery.textScalerOf(context).scale(14) <= 18;

class CollectionListHeader extends StatelessWidget {
  const CollectionListHeader({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => _collectionColumns(context, c.maxWidth)
        ? const Padding(
            padding: EdgeInsets.only(top: 16),
            child: AdminColumnRow(
              widths: _collectionColumnWidths,
              header: true,
              children: [
                Text('Bộ sưu tập'),
                Text('Phong cách'),
                Text('Thứ tự'),
                Text('Trạng thái'),
                Text('Sản phẩm'),
                Text('Cập nhật'),
                Text('Thao tác'),
              ],
            ),
          )
        : const SizedBox.shrink(),
  );
}

class CollectionOverview extends StatelessWidget {
  const CollectionOverview({
    super.key,
    required this.summary,
    required this.status,
    required this.onSelect,
  });
  final AdminRecord summary;
  final String status;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
      final columns = constraints.maxWidth >= 850 && !largeText
          ? 4
          : constraints.maxWidth >= 300 && !largeText
          ? 2
          : 1;
      final items = [
        (
          '',
          'Tổng bộ sưu tập',
          'total',
          Icons.collections_bookmark_outlined,
          T.accent,
        ),
        (
          'published',
          'Đang hiển thị',
          'published',
          Icons.visibility_outlined,
          T.success,
        ),
        ('hidden', 'Đang ẩn', 'hidden', Icons.visibility_off_outlined, T.muted),
        (
          'waiting',
          'Chờ sản phẩm',
          'waiting',
          Icons.hourglass_empty_rounded,
          T.warning,
        ),
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                child: Semantics(
                  selected: status == item.$1,
                  child: Material(
                    color: status == item.$1 ? T.soft : T.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: T.radius,
                      side: BorderSide(
                        color: status == item.$1 ? T.accent : T.line,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: T.radius,
                      onTap: () => onSelect(item.$1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$2, style: T.small),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    adminNumber(summary[item.$3]),
                                    style: T
                                        .display(28)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Icon(item.$4, size: 22, color: item.$5),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

enum CollectionListAction { visibility, storefront, delete }

class CollectionListItem extends StatelessWidget {
  const CollectionListItem({
    super.key,
    required this.row,
    required this.status,
    required this.published,
    required this.onOpen,
    required this.onEdit,
    required this.onAction,
  });
  final AdminRecord row;
  final Widget status;
  final bool published;
  final VoidCallback onOpen, onEdit;
  final ValueChanged<CollectionListAction> onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
      final wide = _collectionColumns(context, constraints.maxWidth);
      final stack = constraints.maxWidth < 260 || largeText;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['title'],
            style: T.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text('/collections/${row['slug']}', style: T.small),
          if (!wide) ...[
            const SizedBox(height: 8),
            Text(
              'Phong cách: ${row['style']} · Thứ tự ${row['position'] ?? 0}',
              style: T.small,
            ),
          ],
        ],
      );
      final cover = ClipRRect(
        borderRadius: T.radius,
        child: SizedBox(
          width: wide
              ? 48
              : stack
              ? 64
              : 76,
          height: wide
              ? 64
              : stack
              ? 80
              : 96,
          child: ColoredBox(
            color: T.canvas,
            child: row['cover'] == null
                ? const Center(
                    child: Icon(Icons.photo_library_outlined, color: T.muted),
                  )
                : FashionImage(
                    row['cover']['url'],
                    label: row['title'],
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      );
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(width: 16),
          Expanded(child: title),
        ],
      );
      final visibility = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!wide) ...[
            const Text('Trạng thái', style: T.small),
            const SizedBox(height: 6),
          ],
          status,
          const SizedBox(height: 8),
          Text(
            'Cập nhật ${adminOrderDate(row['updatedAt']).split(' · ').first}',
            style: T.small,
          ),
        ],
      );
      final products = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!wide) ...[
            const Text('Sản phẩm', style: T.small),
            const SizedBox(height: 6),
          ],
          Text(
            '${adminNumber(row['productCount'])} công khai',
            style: T.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '/ ${adminNumber(row['totalProducts'])} sản phẩm',
            style: T.small,
          ),
        ],
      );
      final menu = PopupMenuButton<CollectionListAction>(
        tooltip: 'Thao tác khác: ${row['title']}',
        icon: const Icon(Icons.more_horiz),
        onSelected: onAction,
        itemBuilder: (_) => [
          PopupMenuItem(
            value: CollectionListAction.visibility,
            child: Text(
              row['active'] == true ? 'Ẩn bộ sưu tập' : 'Hiện bộ sưu tập',
            ),
          ),
          if (published)
            const PopupMenuItem(
              value: CollectionListAction.storefront,
              child: Text('Xem tại cửa hàng'),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: CollectionListAction.delete,
            child: Text('Xóa bộ sưu tập', style: TextStyle(color: T.danger)),
          ),
        ],
      );
      return Container(
        padding: EdgeInsets.symmetric(vertical: wide ? 12 : 20),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: T.line)),
        ),
        child: wide
            ? AdminColumnRow(
                widths: _collectionColumnWidths,
                children: [
                  identity,
                  Text('${row['style']}', style: T.body),
                  Text('${row['position'] ?? 0}', style: T.body),
                  Align(alignment: Alignment.centerLeft, child: status),
                  products,
                  Text(
                    adminOrderDate(row['updatedAt']).split(' · ').first,
                    style: T.small,
                  ),
                  AdminRowActions(
                    onOpen: onOpen,
                    edit: TextButton(
                      onPressed: onEdit,
                      child: const Text('Chỉnh sửa'),
                    ),
                    menu: menu,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stack)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [cover, const SizedBox(height: 12), title],
                    )
                  else
                    identity,
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [visibility, products],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppButton(
                        'Xem chi tiết',
                        outlined: true,
                        onPressed: onOpen,
                      ),
                      TextButton(
                        onPressed: onEdit,
                        child: const Text('Chỉnh sửa'),
                      ),
                      menu,
                    ],
                  ),
                ],
              ),
      );
    },
  );
}
