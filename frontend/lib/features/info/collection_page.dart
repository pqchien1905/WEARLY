import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/collection_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';

class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key, this.slug, this.uri});
  final String? slug;
  final Uri? uri;
  Uri get location =>
      uri ?? Uri(path: slug == null ? '/collections' : '/collections/$slug');
  void change(BuildContext context, String key, String? value) {
    final parameters = {...location.queryParameters}..remove('page');
    if (value == null || value.isEmpty) {
      parameters.remove(key);
    } else {
      parameters[key] = value;
    }
    context.go(
      Uri(
        path: location.path,
        queryParameters: parameters.isEmpty ? null : parameters,
      ).toString(),
    );
  }

  Widget retry(WidgetRef ref, {required bool detail}) => StatePanel(
    title: 'Chưa tải được bộ sưu tập',
    message: 'Kiểm tra kết nối rồi thử lại để xem các thiết kế hiện có.',
    action: AppButton(
      'Thử lại',
      onPressed: () => detail
          ? ref.invalidate(collectionDetailProvider(location.toString()))
          : ref.invalidate(collectionsProvider(location.query)),
    ),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    child: slug == null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trang chủ / Bộ sưu tập', style: T.small),
              const SizedBox(height: 28),
              Text(
                'Một tủ đồ, nhiều cảm hứng.',
                style: T.display(
                  MediaQuery.sizeOf(context).width < 600 ? 36 : 52,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Khám phá những thiết kế đang có, theo phong cách của bạn.',
                style: T.body,
              ),
              const SizedBox(height: 32),
              ref
                  .watch(collectionsProvider(location.query))
                  .when(
                    skipLoadingOnRefresh: false,
                    loading: () => const LoadingPanel(),
                    error: (_, _) => retry(ref, detail: false),
                    data: (data) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${data.total} bộ sưu tập', style: T.small),
                        const SizedBox(height: 24),
                        if (data.items.isEmpty)
                          StatePanel(
                            title: data.total > 0
                                ? 'Trang này không còn bộ sưu tập'
                                : 'Bộ sưu tập đang được cập nhật',
                            message: data.total > 0
                                ? 'Trở về trang đầu để xem các bộ sưu tập hiện có.'
                                : 'Bạn vẫn có thể xem những thiết kế đang bán trong cửa hàng.',
                            action: AppButton(
                              data.total > 0
                                  ? 'Về trang đầu'
                                  : 'Khám phá cửa hàng',
                              onPressed: () => data.total > 0
                                  ? change(context, 'page', null)
                                  : context.go('/shop'),
                            ),
                          )
                        else
                          LayoutBuilder(
                            builder: (_, constraints) {
                              final columns = constraints.maxWidth >= 700
                                  ? 2
                                  : 1;
                              final gap = constraints.maxWidth >= 700
                                  ? 32.0
                                  : 24.0;
                              return Wrap(
                                spacing: gap,
                                runSpacing: 40,
                                children: [
                                  for (final collection in data.items)
                                    SizedBox(
                                      width:
                                          (constraints.maxWidth -
                                              gap * (columns - 1)) /
                                          columns,
                                      child: _CollectionCard(collection),
                                    ),
                                ],
                              );
                            },
                          ),
                        _Pages(
                          page: data.page,
                          limit: data.limit,
                          total: data.total,
                          onPage: (page) => change(context, 'page', '$page'),
                        ),
                      ],
                    ),
                  ),
            ],
          )
        : ref
              .watch(collectionDetailProvider(location.toString()))
              .when(
                skipLoadingOnRefresh: false,
                loading: () => const LoadingPanel(),
                error: (_, _) => retry(ref, detail: true),
                data: (data) {
                  if (data == null) {
                    return StatePanel(
                      title: 'Chưa tìm thấy bộ sưu tập',
                      message: 'Bộ sưu tập này chưa được mở hoặc đã được ẩn.',
                      action: AppButton(
                        'Xem bộ sưu tập',
                        onPressed: () => context.go('/collections'),
                      ),
                    );
                  }
                  final collection = data.collection;
                  final sort = location.queryParameters['sort'] ?? 'newest';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => context.go('/collections'),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Tất cả bộ sưu tập'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CollectionHero(collection),
                      const SizedBox(height: 40),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              '${data.total} thiết kế',
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('Chỉ hàng còn sẵn'),
                                selected:
                                    location.queryParameters['stock'] == 'true',
                                onSelected: (selected) => change(
                                  context,
                                  'stock',
                                  selected ? 'true' : null,
                                ),
                              ),
                              DropdownButton<String>(
                                value:
                                    const [
                                      'newest',
                                      'price-asc',
                                      'price-desc',
                                      'name',
                                    ].contains(sort)
                                    ? sort
                                    : 'newest',
                                underline: const SizedBox(),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'newest',
                                    child: Text('Mới nhất'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'price-asc',
                                    child: Text('Giá tăng dần'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'price-desc',
                                    child: Text('Giá giảm dần'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'name',
                                    child: Text('Theo tên'),
                                  ),
                                ],
                                onChanged: (value) =>
                                    change(context, 'sort', value),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (data.items.isNotEmpty)
                        ProductGrid(data.items, maxColumns: 4)
                      else
                        StatePanel(
                          title: data.total > 0
                              ? 'Trang này không còn sản phẩm'
                              : 'Chưa có thiết kế phù hợp',
                          message: data.total > 0
                              ? 'Trở về trang đầu để xem các thiết kế hiện có.'
                              : 'Thử bỏ bộ lọc hoặc khám phá một bộ sưu tập khác.',
                          action: AppButton(
                            data.total > 0
                                ? 'Về trang đầu'
                                : 'Xem lại bộ sưu tập',
                            onPressed: () => context.go(
                              Uri(
                                path: location.path,
                                queryParameters: data.total > 0
                                    ? ({...location.queryParameters}
                                        ..remove('page'))
                                    : null,
                              ).toString(),
                            ),
                          ),
                        ),
                      if (data.items.isNotEmpty)
                        _Pages(
                          page: data.page,
                          limit: data.limit,
                          total: data.total,
                          onPage: (page) => change(context, 'page', '$page'),
                        ),
                      const SizedBox(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          'Lọc thêm trong cửa hàng',
                          outlined: true,
                          icon: Icons.tune,
                          onPressed: () => context.go(
                            Uri(
                              path: '/shop',
                              queryParameters: {'style': collection.style},
                            ).toString(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
  );
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard(this.collection);
  final StoreCollection collection;
  @override
  Widget build(BuildContext context) {
    void open() =>
        context.go('/collections/${Uri.encodeComponent(collection.slug)}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Mở bộ sưu tập ${collection.title}',
          child: InkWell(
            onTap: open,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FashionImage(
                    collection.image ?? '',
                    label: collection.imageLabel,
                    fit: BoxFit.contain,
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: T.surface,
                        borderRadius: T.radius,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          '${collection.productCount} thiết kế',
                          style: T.small.copyWith(color: T.ink),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 16,
                    right: 16,
                    child: CircleAvatar(
                      backgroundColor: T.surface,
                      foregroundColor: T.ink,
                      child: Icon(Icons.north_east, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(collection.style, style: T.small.copyWith(color: T.accent)),
        const SizedBox(height: 10),
        Text(
          collection.title,
          style: T.display(MediaQuery.sizeOf(context).width < 600 ? 28 : 32),
        ),
        const SizedBox(height: 12),
        Text(collection.description, style: T.body.copyWith(color: T.muted)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: open,
          label: Text('Khám phá ${collection.style.toLowerCase()}'),
          icon: const Icon(Icons.arrow_forward, size: 18),
          iconAlignment: IconAlignment.end,
        ),
      ],
    );
  }
}

class _CollectionHero extends StatelessWidget {
  const _CollectionHero(this.collection);
  final StoreCollection collection;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(collection.style, style: T.small.copyWith(color: T.accent)),
          const SizedBox(height: 16),
          Text(
            collection.title,
            style: T.display(constraints.maxWidth < 600 ? 36 : 48),
          ),
          const SizedBox(height: 20),
          Text(collection.description, style: T.body.copyWith(color: T.muted)),
          const SizedBox(height: 20),
          Text(
            '${collection.productCount} thiết kế trong bộ sưu tập',
            style: T.small,
          ),
        ],
      );
      final image = collection.image == null
          ? null
          : FashionImage(
              collection.image!,
              label: collection.imageLabel,
              fit: BoxFit.contain,
            );
      return DecoratedBox(
        decoration: const BoxDecoration(color: T.canvas),
        child: Padding(
          padding: EdgeInsets.all(constraints.maxWidth < 700 ? 24 : 40),
          child: constraints.maxWidth >= 850 && image != null
              ? Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 40),
                    SizedBox(width: 300, height: 300, child: image),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    if (image != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(height: 240, child: image),
                    ],
                  ],
                ),
        ),
      );
    },
  );
}

class _Pages extends StatelessWidget {
  const _Pages({
    required this.page,
    required this.limit,
    required this.total,
    required this.onPage,
  });
  final int page, limit, total;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => total <= limit
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                'Trang trước',
                outlined: true,
                onPressed: page > 1 ? () => onPage(page - 1) : null,
              ),
              Text('Trang $page / ${(total / limit).ceil()}'),
              AppButton(
                'Trang sau',
                outlined: true,
                onPressed: page * limit < total ? () => onPage(page + 1) : null,
              ),
            ],
          ),
        );
}
