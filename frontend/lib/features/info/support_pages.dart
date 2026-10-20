import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/api_providers.dart';
import '../../app/config.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});
  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      message = TextEditingController();
  bool sent = false;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cùng bạn chọn đồ.',
          style: T.display(MediaQuery.sizeOf(context).width < 600 ? 36 : 52),
        ),
        const SizedBox(height: 16),
        const Text(
          'Cần chọn size, xem đơn hay tìm hiểu phòng thử? Bắt đầu từ điều bạn muốn biết.',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              'Xem câu hỏi thường gặp',
              outlined: true,
              onPressed: () => context.go('/faq'),
            ),
            TextButton(
              onPressed: () => context.go('/account/orders'),
              child: const Text('Xem đơn của tôi'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: sent
              ? StatePanel(
                  title: 'Đã hoàn tất yêu cầu mô phỏng',
                  message:
                      'Không có email được gửi hoặc nội dung được lưu. Khi cửa hàng hoạt động, đội ngũ hỗ trợ sẽ phản hồi qua email của bạn.',
                  action: AppButton(
                    'Viết yêu cầu khác',
                    outlined: true,
                    onPressed: () => setState(() => sent = false),
                  ),
                )
              : Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DemoNotice(
                        text:
                            'Biểu mẫu demo, không gửi đến người nhận. Dùng thông tin minh họa để trải nghiệm.',
                      ),
                      const SizedBox(height: 24),
                      AppField(
                        label: 'Tên của bạn',
                        controller: name,
                        validator: requiredValue,
                      ),
                      const SizedBox(height: 20),
                      AppField(
                        label: 'Email liên hệ',
                        controller: email,
                        validator: emailValidator,
                      ),
                      const SizedBox(height: 20),
                      AppField(
                        label: 'Nội dung cần hỗ trợ',
                        controller: message,
                        maxLines: 4,
                        validator: requiredValue,
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        'Gửi yêu cầu demo',
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          name.clear();
                          email.clear();
                          message.clear();
                          setState(() => sent = true);
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '${BrandConfig.email} · Địa chỉ minh họa, chưa nhận thư',
                        style: T.small,
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 48),
      ],
    ),
  );
}

class FaqPage extends ConsumerWidget {
  const FaqPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    return PageBody(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Những điều bạn muốn biết.',
              style: T.display(
                MediaQuery.sizeOf(context).width < 600 ? 36 : 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              remote
                  ? 'Thông tin về cửa hàng trực tuyến và các tính năng hiện có.'
                  : 'Thông tin dưới đây dành cho trải nghiệm Wearly demo.',
            ),
            const SizedBox(height: 32),
            for (final item in [
              (
                'Làm sao chọn size phù hợp?',
                'Mở bảng size ở trang sản phẩm, đo vòng ngực, eo và hông rồi đối chiếu. Bảng số đo là minh họa; ảnh thử đồ không xác nhận độ vừa vặn.',
              ),
              (
                remote
                    ? 'Đặt hàng ở đây được xử lý thế nào?'
                    : 'Đặt hàng ở đây có bị tính tiền không?',
                remote
                    ? 'Đơn COD được lưu trên máy chủ và có thể xem lại sau khi đăng nhập. Hiện chưa có thanh toán trực tuyến. Trạng thái giao hàng không đồng nghĩa đã xác nhận thu tiền.'
                    : 'Không. Checkout chỉ tạo đơn trong phiên demo, không thu tiền và không gửi hàng. Tải lại trang sẽ xóa đơn.',
              ),
              (
                'Ảnh của tôi có được tải lên mạng không?',
                remote
                    ? 'Phòng thử AI chưa được kết nối trong chế độ trực tuyến. Trang phòng thử hiện tại không gửi ảnh của bạn lên máy chủ.'
                    : 'Không. Ảnh nằm trong bộ nhớ của tab. Xóa ảnh hoặc rời phòng thử sẽ giải phóng ảnh; trang kết quả chỉ giữ thông tin mô phỏng, không chứa ảnh cá nhân.',
              ),
              (
                'Stylist và thử đồ có dùng AI thật không?',
                remote
                    ? 'Chưa. Các trang Stylist và thử đồ trực tuyến thông báo chưa khả dụng; không tạo hoặc hiển thị kết quả AI giả.'
                    : 'Chưa. Stylist chọn sản phẩm từ catalog theo lựa chọn của bạn. Phòng thử hiển thị tiến trình và kết quả minh họa, không tạo ảnh mặc thử thực tế.',
              ),
              (
                'Có thể đổi size hoặc trả hàng không?',
                remote
                    ? 'Xem trang Giao hàng & đổi trả để đọc chính sách cửa hàng đã xuất bản. Khi chưa có chính sách được xác nhận, trang sẽ ghi rõ nội dung demo.'
                    : 'Chính sách demo cho phép đổi size trong 7 ngày khi chưa sử dụng. Chưa có dịch vụ đổi trả thực tế; chính sách sẽ được xác nhận trước khi mở bán.',
              ),
              (
                'Vì sao ảnh không đổi khi chọn một số màu?',
                'Bộ ảnh demo chưa có đủ ảnh cho từng màu. Trang sản phẩm thông báo khi ảnh màu đã chọn chưa có; swatch chỉ đại diện lựa chọn SKU.',
              ),
            ])
              ExpansionTile(
                key: PageStorageKey('faq:${item.$1}'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  item.$1,
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(item.$2),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            if (remote) ...[
              AppButton(
                'Xem chính sách cửa hàng',
                outlined: true,
                onPressed: () => context.go('/shipping-returns'),
              ),
              const SizedBox(height: 16),
            ],
            AppButton(
              'Liên hệ hỗ trợ',
              outlined: true,
              onPressed: () => context.go('/contact'),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
