import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import '../core/design/tokens.dart';
import '../core/widgets/store_shell.dart';
import '../core/widgets/primitives.dart';
import '../core/widgets/motion_widgets.dart';
import '../features/home/home_page.dart';
import '../features/catalog/catalog_page.dart';
import '../features/product_detail/product_page.dart';
import '../features/info/info_page.dart';
import '../features/info/support_pages.dart';
import '../features/info/collection_page.dart';
import 'config.dart';
import 'remote_route_gate.dart';
import '../features/cart/cart_page.dart';
import '../features/checkout/checkout_page.dart';
import '../features/ai_stylist/stylist_page.dart';
import '../features/virtual_tryon/tryon_page.dart';
import '../features/virtual_tryon/tryon_results.dart';
import '../features/account/account_page.dart';
import '../features/account/orders_page.dart';
import '../features/account/address_page.dart';
import '../features/account/style_page.dart';
import '../features/account/tryon_history_page.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/admin_products.dart';
import '../features/admin/admin_pages.dart';

GoRoute appRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
}) => GoRoute(
  path: path,
  pageBuilder: (c, s) => NoTransitionPage(
    key: ValueKey(s.uri.toString()),
    child: SingleChildScrollView(
      key: PageStorageKey(s.uri.toString()),
      padding: path.startsWith('/admin')
          ? EdgeInsets.all(MediaQuery.sizeOf(c).width >= 1024 ? 32 : 20)
          : EdgeInsets.zero,
      child: PageReveal(
        child: path.startsWith('/admin')
            ? RemoteRouteGate(path: s.uri.path, child: builder(c, s))
            : Column(
                children: [
                  RemoteRouteGate(path: s.uri.path, child: builder(c, s)),
                  const StoreFooter(),
                ],
              ),
      ),
    ),
  ),
);

GoRouter createRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  errorBuilder: (c, s) => StoreShell(
    child: StatePanel(
      title: 'Trang này không còn ở đây',
      message: 'Đường dẫn không đúng hoặc đã thay đổi.',
      action: AppButton('Về trang chủ', onPressed: () => c.go('/')),
    ),
  ),
  routes: [
    ShellRoute(
      builder: (_, _, child) => AdminShell(child: child),
      routes: [
        appRoute(path: '/admin', builder: (_, _) => const AdminDashboard()),
        appRoute(
          path: '/admin/products',
          builder: (_, _) => const AdminProductsPage(),
        ),
        appRoute(
          path: '/admin/products/new',
          builder: (_, _) => const AdminProductForm(),
        ),
        appRoute(
          path: '/admin/products/:id/edit',
          builder: (_, s) => AdminProductForm(id: s.pathParameters['id']),
        ),
        appRoute(
          path: '/admin/inventory',
          builder: (_, _) => const AdminProductsPage(inventory: true),
        ),
        appRoute(
          path: '/admin/orders',
          builder: (_, _) => const AdminOrdersPage(),
        ),
        appRoute(
          path: '/admin/orders/:id',
          builder: (_, s) => AdminOrdersPage(id: s.pathParameters['id']),
        ),
        appRoute(
          path: '/admin/customers',
          builder: (_, _) => const AdminCustomersPage(),
        ),
        appRoute(
          path: '/admin/promotions',
          builder: (_, _) => const AdminPromotionsPage(),
        ),
        appRoute(
          path: '/admin/content',
          builder: (_, _) => const AdminContentPage(),
        ),
        appRoute(
          path: '/admin/ai-monitoring',
          builder: (_, _) => const AdminMonitoringPage(),
        ),
        appRoute(
          path: '/admin/settings',
          builder: (_, _) => const AdminSettingsPage(),
        ),
      ],
    ),
    ShellRoute(
      builder: (_, _, child) => StoreShell(child: child),
      routes: [
        appRoute(
          path: '/403',
          builder: (c, _) => StatePanel(
            title: 'Bạn chưa có quyền truy cập',
            message:
                'Trạng thái 403 mô phỏng. Khi kết nối máy chủ, quyền truy cập được xác minh ở đó.',
            icon: Icons.lock_outline,
            action: AppButton('Về cửa hàng', onPressed: () => c.go('/')),
          ),
        ),
        appRoute(path: '/', builder: (_, _) => const HomePage()),
        for (final path in ['/login', '/register', '/forgot-password'])
          appRoute(
            path: path,
            builder: (_, s) =>
                AuthPage(key: ValueKey(s.uri.path), mode: s.uri.path),
          ),
        appRoute(path: '/account', builder: (_, _) => const AccountPage()),
        appRoute(
          path: '/account/addresses',
          builder: (_, _) => const AddressPage(),
        ),
        appRoute(path: '/account/style', builder: (_, _) => const StylePage()),
        appRoute(
          path: '/account/try-ons',
          builder: (_, _) => const TryOnHistoryPage(),
        ),
        appRoute(
          path: '/account/orders',
          builder: (_, _) => const OrdersPage(),
        ),
        appRoute(
          path: '/account/orders/:id',
          builder: (_, s) => OrdersPage(id: s.pathParameters['id']),
        ),
        appRoute(
          path: '/ai-stylist',
          builder: (_, s) =>
              StylistPage(prompt: s.uri.queryParameters['prompt']),
        ),
        appRoute(
          path: '/virtual-try-on',
          builder: (_, s) => TryOnPage(slug: s.uri.queryParameters['product']),
        ),
        appRoute(
          path: '/virtual-try-on/:jobId',
          builder: (_, s) => TryOnResultPage(id: s.pathParameters['jobId']!),
        ),
        appRoute(path: '/cart', builder: (_, _) => const CartPage()),
        appRoute(path: '/checkout', builder: (_, _) => const CheckoutPage()),
        appRoute(
          path: '/checkout/success/:id',
          builder: (_, s) => OrderSuccessPage(id: s.pathParameters['id']!),
        ),
        for (final path in ['/shop', '/search'])
          appRoute(
            path: path,
            builder: (_, s) => CatalogPage(uri: s.uri),
          ),
        appRoute(
          path: '/wishlist',
          builder: (_, s) => CatalogPage(uri: s.uri, wishlist: true),
        ),
        appRoute(
          path: '/products/:slug',
          builder: (_, s) => ProductPageView(slug: s.pathParameters['slug']!),
        ),
        appRoute(
          path: '/design-system',
          builder: (_, _) => const GalleryPage(),
        ),
        appRoute(path: '/contact', builder: (_, _) => const ContactPage()),
        appRoute(path: '/faq', builder: (_, _) => const FaqPage()),
        appRoute(
          path: '/collections',
          builder: (_, _) => const CollectionPage(),
        ),
        appRoute(
          path: '/collections/:slug',
          builder: (_, s) => CollectionPage(slug: s.pathParameters['slug']),
        ),
        for (final page in [
          '/about',
          '/shipping-returns',
          '/privacy',
          '/size-guide',
        ])
          appRoute(
            path: page,
            builder: (_, s) => InfoPage(path: s.uri.path),
          ),
      ],
    ),
  ],
);

class NepApp extends StatefulWidget {
  const NepApp({super.key, this.router});
  final GoRouter? router;
  @override
  State<NepApp> createState() => _NepAppState();
}

class _NepAppState extends State<NepApp> {
  late final router = widget.router ?? createRouter();
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: BrandConfig.title,
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    builder: (context, child) => Theme(
      data: buildTheme(reduceMotion: MediaQuery.disableAnimationsOf(context)),
      child: child!,
    ),
    routerConfig: router,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
  );
}
