import '../../app/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../core/widgets/store_content.dart';
import '../product_detail/product_page.dart';

class InfoPage extends ConsumerWidget {
  const InfoPage({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    final content = switch (path) {
      '/collections' => (
        'Everyday, theo cách bạn.',
        'Một chiếc áo trắng, một phom quần rộng, một chiếc đầm có sắc màu riêng. Bộ sưu tập minh họa những cách phối đơn giản cho nhịp sống hằng ngày.',
      ),
      '/privacy' => (
        remote
            ? 'Dữ liệu khi kết nối cửa hàng'
            : 'Quyền riêng tư trong bản demo',
        remote
            ? 'Tài khoản, địa chỉ, giỏ hàng, đơn hàng, yêu thích, đánh giá và hồ sơ phong cách được lưu trên máy chủ. Tải lại trang không xóa các dữ liệu này. Phiên đăng nhập chỉ được giữ trong bộ nhớ của tab; sau khi tải lại, bạn cần đăng nhập lại. Quản trị viên được phân quyền có thể xem thông tin cần thiết để quản lý tài khoản và xử lý đơn hàng. Phòng thử AI chưa được kết nối trong chế độ trực tuyến hiện tại.'
            : 'Ảnh bạn chọn chỉ được giữ trong bộ nhớ của tab hiện tại, không được tải lên máy chủ hoặc lưu vào browser storage. Xóa ảnh hoặc rời phòng thử để giải phóng ảnh. Tài khoản, giỏ hàng và đơn hàng là dữ liệu mô phỏng, mất khi tải lại ứng dụng. Không nhập thông tin cá nhân thật nếu không cần thiết.',
      ),
      '/shipping-returns' => (
        'Giao hàng & đổi trả',
        'Chính sách demo: giao tiêu chuẩn 30.000đ trong 3–5 ngày; miễn phí từ 1.500.000đ. Giao nhanh 50.000đ. Đổi size trong 7 ngày khi chưa sử dụng. Bản demo không tạo vận đơn, giao hàng hoặc thu tiền. Chính sách thật sẽ được xác nhận trước khi mở bán.',
      ),
      '/size-guide' => (
        'Một lựa chọn vừa vặn hơn',
        'Bảng size là dữ liệu tham khảo. Đo vòng ngực, eo và hông bằng thước dây; so với số đo trước khi chọn. Ảnh thử đồ mô phỏng không xác nhận độ vừa vặn.',
      ),
      _ => (
        'Ít hơn, nhưng đúng với bạn.',
        '${BrandConfig.displayName} là ý tưởng về một tủ đồ đương đại: những phom dáng dễ kết hợp, chất liệu dễ chịu và màu sắc có chiều sâu. Đây là thương hiệu placeholder cho bản trình diễn, cùng catalog và ảnh minh họa. Không đại diện cho cửa hàng đang bán hàng thực tế.',
      ),
    };
    return PageBody(
      vertical: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.$1,
                  style: T.display(
                    MediaQuery.sizeOf(context).width < 600 ? 36 : 56,
                  ),
                ),
                const SizedBox(height: 32),
                if (path == '/shipping-returns')
                  StoreContentText(
                    field: 'policy',
                    fallback: content.$2,
                    style: T.body.copyWith(fontSize: 16),
                  )
                else
                  Text(content.$2, style: T.body.copyWith(fontSize: 16)),
                const SizedBox(height: 32),
                if (path == '/size-guide')
                  AppButton(
                    'Mở bảng số đo',
                    onPressed: () => showSizeGuide(context),
                  )
                else
                  AppButton(
                    'Khám phá thiết kế',
                    onPressed: () => context.go('/shop'),
                  ),
              ],
            ),
          ),
          if (path == '/collections') ...[
            const SizedBox(height: 40),
            const AspectRatio(
              aspectRatio: 2,
              child: FashionImage(
                'assets/images/shirt.jpg',
                label: 'Bộ sưu tập Everyday minh họa',
                alignment: Alignment(0, -.5),
              ),
            ),
          ],
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}

class GalleryPage extends ConsumerWidget {
  const GalleryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${BrandConfig.displayName} / Design system',
          style: T.display(40),
        ),
        const SizedBox(height: 24),
        const Text('Tokens, thành phần và trạng thái dùng chung.'),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final color in [
              T.ink,
              T.accent,
              T.soft,
              T.canvas,
              T.success,
              T.danger,
            ])
              Container(width: 100, height: 80, color: color),
          ],
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            AppButton(
              'Primary',
              onPressed: () => toast(context, 'Đã kích hoạt'),
            ),
            AppButton(
              'Secondary',
              outlined: true,
              onPressed: () => toast(context, 'Đã kích hoạt'),
            ),
            const AppButton('Disabled'),
            const AppButton('Đang xử lý', busy: true),
          ],
        ),
        const SizedBox(height: 32),
        const AppField(label: 'Tên của bạn'),
        const SizedBox(height: 24),
        const DemoNotice(),
        const SizedBox(height: 24),
        const StatePanel(
          title: 'Chưa có sản phẩm',
          message: 'Hãy bắt đầu từ bộ sưu tập.',
        ),
        ref
            .watch(catalogProvider(''))
            .when(
              data: (p) => ProductGrid(p.items.take(4).toList()),
              error: (_, _) => const Text('Không tải được gallery'),
              loading: () => const LoadingPanel(),
            ),
      ],
    ),
  );
}
