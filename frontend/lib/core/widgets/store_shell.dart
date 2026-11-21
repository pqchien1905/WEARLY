import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/config.dart';
import '../../app/content_provider.dart';
import 'store_content.dart';
import '../../app/api_providers.dart';
import '../../app/providers.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../design/store_header_style.dart';
import 'primitives.dart';
import 'store_header_actions.dart';
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final mobile = viewportWidth < 1200 || viewportWidth < 1200 * textScale;
    final stackedActions = viewportWidth < 600;
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
                        fontSize: mobile ? 11 : 12,
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
          StoreUtilityBar(path: path, horizontalPadding: mobile ? 12 : 48),
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
                    vertical: StoreHeaderStyle.verticalPadding,
                  ),
                  child: Column(
                    children: [
                      Row(
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
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width < 380
                                    ? 100
                                    : 140,
                              ),
                              child: const BrandMark(),
                            ),
                          ),
                          const Spacer(),
                          if (!mobile) ...[
                            for (final item in navItems)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Semantics(
                                  selected: _navSelected(path, item.$2),
                                  child: AnimatedContainer(
                                    duration: Motion.duration(
                                      context,
                                      Motion.fast,
                                    ),
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
                                        foregroundColor:
                                            _navSelected(path, item.$2)
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
                          if (stackedActions)
                            SizedBox(
                              width: 132,
                              child: StoreHeaderActions(
                                compact: true,
                                openSearch: () => showSearchPanel(context),
                              ),
                            )
                          else
                            SizedBox(
                              width: StoreHeaderStyle.actionsWidth,
                              child: StoreHeaderActions(
                                openSearch: () => showSearchPanel(context),
                              ),
                            ),
                        ],
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

class BrandMark extends ConsumerWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(remoteApiProvider)
        ? (ref
                  .watch(publishedContentProvider)
                  .asData
                  ?.value
                  ?.details?['name'] ??
              'WEARLY')
        : BrandConfig.name;
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          name,
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
  Timer? debounce;
  String query = '';
  @override
  void dispose() {
    debounce?.cancel();
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
                onChanged: (v) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 250), () {
                    if (mounted) setState(() => query = v.trim());
                  });
                },
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

class StoreFooter extends ConsumerStatefulWidget {
  const StoreFooter({super.key});
  @override
  ConsumerState<StoreFooter> createState() => _StoreFooterState();
}

class _StoreFooterState extends ConsumerState<StoreFooter> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  bool consent = false, subscribing = false, subscribed = false;
  String? subscriptionError;
  Future<void> subscribe() async {
    if (subscribing || !form.currentState!.validate()) return;
    if (!consent) {
      setState(
        () => subscriptionError = 'Bạn cần đồng ý nhận tin trước khi đăng ký.',
      );
      return;
    }
    setState(() {
      subscribing = true;
      subscriptionError = null;
    });
    try {
      if (ref.read(remoteApiProvider)) {
        await ref
            .read(apiClientProvider)
            .request(
              'POST',
              'content/newsletter',
              authenticated: false,
              body: {'email': email.text.trim(), 'consent': true},
            );
      }
      if (mounted) {
        setState(() {
          subscribed = true;
          email.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => subscriptionError = '$e');
    } finally {
      if (mounted) setState(() => subscribing = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
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
                      const StoreContentText(
                        field: 'tagline',
                        fallback: 'Tủ đồ đương đại, theo cách bạn.',
                        style: T.body,
                      ),
                      const SizedBox(height: 16),
                      const StoreContactDetails(),
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
                        ('Điều khoản sử dụng', '/terms'),
                        ('Câu chuyện cửa hàng', '/about'),
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
                              keyboardType: TextInputType.emailAddress,
                              readOnly: subscribing || subscribed,
                              onSubmitted: (_) => subscribe(),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: consent,
                              onChanged: subscribing || subscribed
                                  ? null
                                  : (v) => setState(() => consent = v ?? false),
                              title: const Text(
                                'Tôi đồng ý nhận tin về sản phẩm và bộ sưu tập.',
                                style: T.small,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AppButton(
                              subscribed ? 'Đã đăng ký' : 'Đăng ký nhận tin',
                              outlined: true,
                              busy: subscribing,
                              onPressed: subscribed ? null : subscribe,
                            ),
                            if (subscriptionError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    subscriptionError!,
                                    style: T.small.copyWith(color: T.danger),
                                  ),
                                ),
                              ),
                            if (subscribed)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    ref.watch(remoteApiProvider)
                                        ? 'Đã lưu đăng ký nhận tin của bạn. Cảm ơn bạn đã đồng hành cùng WEARLY.'
                                        : 'Đăng ký mô phỏng, không lưu hoặc gửi email.',
                                    style: T.small,
                                  ),
                                ),
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
              const Text('© 2026 WEARLY', style: T.small),
              Text(
                ref.watch(remoteApiProvider)
                    ? 'Phong cách riêng, lựa chọn của bạn.'
                    : 'Catalog & ảnh minh họa. Chưa bán hàng thực tế.',
                style: T.small,
              ),
              if (!ref.watch(remoteApiProvider))
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
