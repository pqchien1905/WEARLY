import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/support_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/store_content.dart';
import '../../data/remote_support.dart';

class RemoteContactPage extends ConsumerStatefulWidget {
  const RemoteContactPage({super.key});
  @override
  ConsumerState<RemoteContactPage> createState() => _RemoteContactPageState();
}

class _RemoteContactPageState extends ConsumerState<RemoteContactPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      message = TextEditingController();
  bool busy = false;
  String? error;
  SupportReceipt? receipt;
  @override
  void initState() {
    super.initState();
    final repo = ref.read(supportRepositoryProvider),
        draft = repo.pendingContact;
    name.text = draft?['name'] as String? ?? '';
    email.text = draft?['email'] as String? ?? '';
    message.text = draft?['message'] as String? ?? '';
    receipt = repo.lastReceipt;
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final repo = ref.read(supportRepositoryProvider);
    if (busy ||
        (repo.pendingContact == null && !form.currentState!.validate())) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await repo.create(
        name: name.text,
        email: email.text,
        message: message.text,
      );
      if (mounted) setState(() => receipt = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa xác nhận được kết quả. Hãy gửi lại cùng yêu cầu.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(supportRepositoryProvider).pendingContact != null;
    return PageBody(
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cùng bạn chọn đồ.',
                style: T.display(
                  MediaQuery.sizeOf(context).width < 600 ? 36 : 52,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cần chọn size, xem đơn hay tìm hiểu phòng thử? Gửi nội dung để cửa hàng hỗ trợ.',
              ),
              const SizedBox(height: 24),
              const StoreContactDetails(),
              if (receipt != null)
                StatePanel(
                  title: 'Đã lưu yêu cầu hỗ trợ',
                  icon: Icons.check_circle_outline,
                  message:
                      'Mã tiếp nhận: ${receipt!.id}\nYêu cầu đã được lưu. Phản hồi sẽ được gửi tới email liên hệ của bạn sau khi cửa hàng trả lời.',
                  action: AppButton(
                    'Viết yêu cầu khác',
                    outlined: true,
                    onPressed: () {
                      ref.read(supportRepositoryProvider).clearReceipt();
                      name.clear();
                      email.clear();
                      message.clear();
                      setState(() => receipt = null);
                    },
                  ),
                )
              else
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Cửa hàng sẽ trả lời qua email liên hệ bạn cung cấp. Không gửi mật khẩu hoặc thông tin thanh toán trong nội dung.',
                        style: T.small,
                      ),
                      const SizedBox(height: 24),
                      if (pending)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Đang giữ nguyên nội dung để gửi lại và tránh tạo yêu cầu trùng.',
                          ),
                        ),
                      TextFormField(
                        controller: name,
                        readOnly: busy || pending,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Tên của bạn',
                        ),
                        validator: (v) => (v ?? '').trim().length >= 2
                            ? null
                            : 'Nhập tên từ 2 đến 100 ký tự.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: email,
                        readOnly: busy || pending,
                        maxLength: 254,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email liên hệ',
                        ),
                        validator: emailValidator,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: message,
                        readOnly: busy || pending,
                        maxLength: 3000,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung cần hỗ trợ',
                        ),
                        validator: (v) => (v ?? '').trim().length >= 10
                            ? null
                            : 'Nhập nội dung từ 10 đến 3000 ký tự.',
                      ),
                      const SizedBox(height: 16),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(color: T.danger),
                          ),
                        ),
                      AppButton(
                        pending ? 'Gửi lại cùng yêu cầu' : 'Gửi yêu cầu hỗ trợ',
                        busy: busy,
                        onPressed: send,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
