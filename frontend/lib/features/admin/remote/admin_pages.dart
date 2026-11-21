import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../../core/widgets/primitives.dart';

import 'product_editor.dart';
import 'products_page.dart';
import 'product_detail.dart';
import 'inventory_page.dart';
import 'inventory_detail.dart';
import 'brands_page.dart';
import 'categories_page.dart';
import 'collections_page.dart';
import 'admin_dashboard.dart';
import 'orders_page.dart';
import 'customers_page.dart';
import 'customer_detail.dart';
import 'order_detail.dart';
export 'order_detail.dart' show RemoteAdminOrder;
import 'content_page.dart';
import 'newsletter_page.dart';
import 'reviews_page.dart';
import 'promotions_page.dart';
import 'support_page.dart';
import 'staff_page.dart';
import 'operations_page.dart';

class RemoteAdminRoute extends StatelessWidget {
  const RemoteAdminRoute({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) {
    final parts = path.split('/');
    if (path == '/admin') return const RemoteAdminDashboard();
    if (path == '/admin/products') return const RemoteAdminProducts();
    if (path == '/admin/inventory') return const RemoteAdminInventory();
    if (parts.length == 4 && parts[2] == 'inventory') {
      return RemoteInventoryDetail(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (path == '/admin/orders') return const RemoteAdminOrders();
    if (path == '/admin/customers') return const RemoteAdminCustomers();
    if (parts.length == 4 && parts[2] == 'customers') {
      return RemoteAdminCustomer(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (path == '/admin/newsletter') return const RemoteNewsletterPage();
    if (path == '/admin/reviews') return const RemoteReviewsPage();
    if (path == '/admin/content') return const RemoteContentPage();
    if (parts.length == 4 && parts[2] == 'collections') {
      return RemoteCollectionDetail(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (path == '/admin/collections') return const RemoteCollectionsPage();
    if (path.startsWith('/admin/promotions/')) {
      return RemotePromotionDetail(
        id: path.split('/').last,
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (path == '/admin/promotions') return const RemotePromotionsPage();
    if (path == '/admin/support') return const RemoteSupportPage();
    if (path == '/admin/mail') return const RemoteMailPage();
    if (path == '/admin/staff') return const RemoteStaffPage();
    if (path == '/admin/ai-monitoring') return const RemoteOperationsPage();
    if (parts.length == 4 && parts[2] == 'support') {
      return RemoteSupportDetail(id: parts[3]);
    }
    if (path == '/admin/categories') return const RemoteAdminCategories();
    if (parts.length == 4 && parts[2] == 'categories') {
      return RemoteCategoryDetail(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (path == '/admin/brands') {
      return const RemoteAdminBrands();
    }
    if (parts.length == 4 && parts[2] == 'brands') {
      return RemoteBrandDetail(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (path == '/admin/products/new') {
      return RemoteProductEditor(
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (parts.length == 5 && parts[2] == 'products' && parts[4] == 'edit') {
      return RemoteProductEditor(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (parts.length == 4 && parts[2] == 'products') {
      return RemoteAdminProduct(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    if (parts.length == 4 && parts[2] == 'orders') {
      return RemoteAdminOrder(
        id: parts[3],
        returnTo: GoRouterState.of(context).uri.queryParameters['from'],
      );
    }
    return const StatePanel(
      title: 'Chức năng quản trị chưa khả dụng',
      message:
          'Chức năng này chưa được kết nối. Hãy chọn mục có trong menu quản trị.',
    );
  }
}
