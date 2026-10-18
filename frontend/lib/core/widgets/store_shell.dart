import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/config.dart';
import '../../app/api_providers.dart';
import '../../app/providers.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import 'primitives.dart';
import '../../app/commerce_state.dart';
import '../../features/cart/cart_page.dart';
import '../../features/product_detail/product_page.dart';

class StoreShell extends ConsumerStatefulWidget {
  const StoreShell({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends ConsumerState<StoreShell> {
  bool announcement = true;
  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 1200;
    final path = GoRouterState.of(context).uri.path;
    return Scaffold(
      bottomNavigationBar:
          MediaQuery.sizeOf(context).width < 800 &&
              GoRouterState.of(context).uri.path.startsWith('/products/')
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: T.surface,
                  border: Border(top: BorderSide(color: T.line)),
                ),
                child: AppButton(
                  'Chọn size & mua',
                  onPressed: () {
                    final target = purchaseAnchor.currentContext;
                    if (target != null) {
                      Scrollable.ensureVisible(
                        target,
                        alignment: .2,
                        duration: MediaQuery.of(context).disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                      );
                    }
                  },
                ),
              ),
            )
          : null,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const Padding(padding: EdgeInsets.all(24), child: BrandMark()),
              for (final item in navItems)
                ListTile(
                  selected: _navSelected(path, item.$2),
                  title: Text(item.$1),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(item.$2);
                  },
                ),
              ListTile(
                title: const Text('Yêu thích'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/wishlist');
                },
              ),
              ListTile(
                title: const Text('Tài khoản'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/account');
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (announcement)
            Container(
              color: T.accent,
              padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Flexible(
                    flex: 12,
                    child: Text(
                      ref.watch(remoteApiProvider)
                          ? 'Giao miễn phí từ 1.500.000đ · Thanh toán COD'
                          : 'Giao miễn phí từ 1.500.000đ · Chính sách demo',
                      textAlign: TextAlign.center,
                      style: T.small.copyWith(
                        color: T.surface,
                        fontSize: mobile ? 10 : 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Đóng thông báo',
                      onPressed: () => setState(() => announcement = false),
                      icon: const Icon(Icons.close, color: T.surface, size: 15),
                    ),
                  ),
                ],
              ),
            ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: T.surface,
              border: Border(bottom: BorderSide(color: T.line)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: T.maxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: mobile ? 12 : 48,
                    vertical: mobile ? 10 : 16,
                  ),
                  child: Row(
                    children: [
                      if (mobile)
                        Builder(
                          builder: (c) => IconButton(
                            tooltip: 'Mở menu',
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(c).openDrawer(),
                          ),
                        ),
                      InkWell(
                        onTap: () => context.go('/'),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: const BrandMark(),
                        ),
                      ),
                      const Spacer(),
                      if (!mobile) ...[
                        for (final item in navItems)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Semantics(
                              selected: _navSelected(path, item.$2),
                              child: AnimatedContainer(
                                duration: Motion.duration(context, Motion.fast),
                                curve: Motion.curve,
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _navSelected(path, item.$2)
                                          ? T.accent
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: _navSelected(path, item.$2)
                                        ? T.accent
                                        : T.ink,
                                  ),
                                  onPressed: () => context.go(item.$2),
                                  child: Text(item.$1),
                                ),
                              ),
                            ),
                          ),
                        const Spacer(),
                      ],
                      IconButton(
                        tooltip: 'Tìm kiếm',
                        icon: const Icon(Icons.search),
                        onPressed: () => showSearchPanel(context),
                      ),
                      if (!mobile) ...[
                        IconButton(
                          tooltip: 'Yêu thích',
                          icon: const Icon(Icons.favorite_border),
                          onPressed: () => context.go('/wishlist'),
                        ),
                        IconButton(
                          tooltip: 'Tài khoản',
                          icon: const Icon(Icons.person_outline),
                          onPressed: () => context.go('/account'),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Giỏ hàng',
                        icon: Consumer(
                          builder: (_, ref, _) {
                            final count = ref.watch(commerceProvider).count;
                            return Badge(
                              isLabelVisible: count > 0,
                              label: Text('$count'),
                              child: const Icon(Icons.shopping_bag_outlined),
                            );
                          },
                        ),
                        onPressed: () => showCartDrawer(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Isolate the nested Navigator's BlockSemantics from the header.
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

const navItems = [
  ('Cửa hàng', '/shop'),
  ('Bộ sưu tập', '/collections'),
  ('AI Stylist', '/ai-stylist'),
  ('Phòng thử', '/virtual-try-on'),
];

bool _navSelected(String path, String target) =>
    path == target ||
    path.startsWith('$target/') ||
    (target == '/shop' && (path.startsWith('/products/') || path == '/search'));

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: BrandConfig.title,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        BrandConfig.name,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 38,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: -2,
          color: T.ink,
        ),
      ),
    ),
  );
}

void showSearchPanel(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SearchPanel());

class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});
  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final controller = TextEditingController();
  String query = '';
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void search() {
    final target = Uri(
      path: '/search',
      queryParameters: {'q': controller.text.trim()},
    );
    Navigator.pop(context);
    context.go(target.toString());
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(
      catalogProvider(Uri(queryParameters: {'q': query}).query),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Tìm món đồ của bạn', style: T.display(24)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Đóng tìm kiếm',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                autofocus: true,
                controller: controller,
                onChanged: (v) => setState(() => query = v),
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  labelText: 'Tìm tên sản phẩm, chất liệu',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Xem kết quả',
                    onPressed: search,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: data.when(
                  data: (page) => page.items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Không có gợi ý. Thử “áo” hoặc “đầm”.'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: page.items
                              .take(4)
                              .map(
                                (p) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: SizedBox(
                                    width: 40,
                                    height: 50,
                                    child: FashionImage(p.image, label: p.name),
                                  ),
                                  title: Text(p.name, style: T.body),
                                  trailing: const Icon(
                                    Icons.north_east,
                                    size: 18,
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    context.go('/products/${p.slug}');
                                  },
                                ),
                              )
                              .toList(),
                        ),
                  error: (_, _) =>
                      const Text('Không tải được gợi ý. Hãy thử lại.'),
                  loading: () => const LinearProgressIndicator(),
                ),
              ),
              const SizedBox(height: 16),
              AppButton('Xem tất cả kết quả', onPressed: search),
            ],
          ),
        ),
      ),
    );
  }
}

class StoreFooter extends StatefulWidget {
  const StoreFooter({super.key});
  @override
  State<StoreFooter> createState() => _StoreFooterState();
}

class _StoreFooterState extends State<StoreFooter> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: T.canvas,
    child: PageBody(
      vertical: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (_, c) => Wrap(
              spacing: 64,
              runSpacing: 32,
              children: [
                SizedBox(
                  width: c.maxWidth < 600
                      ? c.maxWidth
                      : c.maxWidth < 1050
                      ? 300
                      : (c.maxWidth - 128) * .38,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: 16),
                      const Text(
                        'Ít hơn, nhưng đúng với bạn.\nNhững món đồ ở lại cùng phong cách.',
                        style: T.body,
                      ),
                      const SizedBox(height: 16),
                      Text(BrandConfig.email, style: T.small),
                    ],
                  ),
                ),
                SizedBox(
                  width: c.maxWidth < 1050 ? 220 : (c.maxWidth - 128) * .24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cùng bạn chọn đồ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final link in [
                        ('Bảng size', '/size-guide'),
                        ('Câu hỏi thường gặp', '/faq'),
                        ('Liên hệ hỗ trợ', '/contact'),
                        ('Giao hàng & đổi trả', '/shipping-returns'),
                        ('Quyền riêng tư', '/privacy'),
                        ('Câu chuyện ${BrandConfig.displayName}', '/about'),
                      ])
                        TextButton(
                          onPressed: () => context.go(link.$2),
                          child: Text(link.$1),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: c.maxWidth < 600
                      ? c.maxWidth
                      : c.maxWidth < 1050
                      ? 350
                      : (c.maxWidth - 128) * .38,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                        key: form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Một chút cảm hứng mới.',
                              style: T.display(24),
                            ),
                            const SizedBox(height: 16),
                            AppField(
                              label: 'Email của bạn',
                              controller: email,
                              validator: emailValidator,
                            ),
                            const SizedBox(height: 12),
                            AppButton(
                              'Đăng ký bản tin demo',
                              outlined: true,
                              onPressed: () {
                                if (form.currentState!.validate()) {
                                  toast(
                                    context,
                                    'Đã đăng ký mô phỏng. Email không được gửi hoặc lưu.',
                                  );
                                  email.clear();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 64),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              const Text(
                '© 2026 ${BrandConfig.displayName} · Thương hiệu minh họa',
                style: T.small,
              ),
              const Text(
                'Catalog & ảnh minh họa. Chưa bán hàng thực tế.',
                style: T.small,
              ),
              TextButton(
                onPressed: () => context.go('/admin'),
                child: const Text('Quản trị demo'),
              ),
              TextButton(
                onPressed: () => context.go('/design-system'),
                child: const Text('Design system'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
