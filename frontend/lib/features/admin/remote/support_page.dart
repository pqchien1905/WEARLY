import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/support_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_support.dart';
import 'admin_widgets.dart';
import 'admin_providers.dart' show staffRoleProvider, canStaff;

class RemoteSupportPage extends ConsumerStatefulWidget {
  const RemoteSupportPage({super.key});
  @override
  ConsumerState<RemoteSupportPage> createState() => _RemoteSupportPageState();
}

class _RemoteSupportPageState extends ConsumerState<RemoteSupportPage> {
  String? cursor;
  final previous = <String?>[];
  @override
  Widget build(BuildContext context) {
    final provider = supportListProvider(cursor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Hỗ trợ khách hàng',
          'Yêu cầu đã được lưu, gồm cả khách chưa đăng nhập.',
          actions: [
            AppButton(
              'Tải lại',
              outlined: true,
              onPressed: () => ref.invalidate(provider),
            ),
            if (canStaff(ref.watch(staffRoleProvider), 'mail.read'))
              AppButton(
                'Theo dõi thư',
                outlined: true,
                onPressed: () => context.go('/admin/mail'),
              ),
          ],
        ),
        AdminAsync(
          value: ref.watch(provider),
          reload: () => ref.invalidate(provider),
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((data['items'] as List).isEmpty)
                const Text('Chưa có yêu cầu hỗ trợ.'),
              for (final row in data['items'])
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['name'],
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      SelectableText(row['email']),
                      const SizedBox(height: 8),
                      Text(
                        supportStatusNames[row['status']] ??
                            'Không rõ trạng thái',
                      ),
                      Text('Mã: ${row['id']}', style: T.small),
                      const SizedBox(height: 12),
                      AppButton(
                        'Xem và trả lời',
                        outlined: true,
                        onPressed: () =>
                            context.go('/admin/support/${row['id']}'),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (previous.isNotEmpty)
                    AppButton(
                      'Trang trước',
                      outlined: true,
                      onPressed: () =>
                          setState(() => cursor = previous.removeLast()),
                    ),
                  if (data['nextCursor'] != null)
                    AppButton(
                      'Trang tiếp',
                      outlined: true,
                      onPressed: () => setState(() {
                        previous.add(cursor);
                        cursor = data['nextCursor'];
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RemoteSupportDetail extends ConsumerStatefulWidget {
  const RemoteSupportDetail({super.key, required this.id});
  final String id;
  @override
  ConsumerState<RemoteSupportDetail> createState() =>
      _RemoteSupportDetailState();
}

class _RemoteSupportDetailState extends ConsumerState<RemoteSupportDetail> {
  final form = GlobalKey<FormState>(), message = TextEditingController();
  bool busy = false, needsReload = false;
  String? error, notice;
  @override
  void initState() {
    super.initState();
    message.text =
        ref
                .read(adminSupportRepositoryProvider)
                .pendingReply(widget.id)?['message']
            as String? ??
        '';
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      ref.invalidate(supportDetailProvider(widget.id));
      await ref.read(supportDetailProvider(widget.id).future);
      if (mounted) {
        setState(() {
          needsReload = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = adminError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(
    Map<String, dynamic> ticket, {
    bool status = false,
  }) async {
    final repo = ref.read(adminSupportRepositoryProvider);
    if (busy ||
        needsReload ||
        (!status &&
            repo.pendingReply(widget.id) == null &&
            !form.currentState!.validate())) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      if (status) {
        await repo.status(
          widget.id,
          version: ticket['version'],
          status: ticket['status'] == 'CLOSED' ? 'OPEN' : 'CLOSED',
        );
      } else {
        await repo.reply(
          widget.id,
          version: ticket['version'],
          message: message.text,
        );
      }
      if (!mounted) return;
      if (!status) {
        message.clear();
        notice = 'Đã lưu trả lời; thư đang được xử lý.';
      }
      ref.invalidate(supportDetailProvider(widget.id));
      ref.invalidate(supportListProvider);
      ref.invalidate(adminMailProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = adminError(e);
          needsReload = status || (e is ApiException && e.status == 409);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = supportDetailProvider(widget.id),
        value = ref.watch(provider),
        pending =
            ref.watch(adminSupportRepositoryProvider).pendingReply(widget.id) !=
            null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Yêu cầu hỗ trợ',
          'Trả lời được lưu trước khi gửi tới hộp thư local.',
          actions: [
            AppButton(
              'Tải lại yêu cầu',
              outlined: true,
              onPressed: busy ? null : reload,
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(error!, style: const TextStyle(color: T.danger)),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(notice!, style: const TextStyle(color: T.success)),
          ),
        AdminAsync(
          value: value,
          reload: reload,
          builder: (ticket) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket['name'],
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SelectableText(ticket['email']),
                    const SizedBox(height: 12),
                    SelectableText(ticket['message']),
                    const SizedBox(height: 16),
                    Text(supportStatusNames[ticket['status']]!),
                    SelectableText('Mã: ${widget.id}', style: T.small),
                    const SizedBox(height: 12),
                    AppButton(
                      ticket['status'] == 'CLOSED'
                          ? 'Mở lại yêu cầu'
                          : 'Đóng yêu cầu',
                      outlined: true,
                      onPressed:
                          busy || pending || needsReload || value.isLoading
                          ? null
                          : () => change(ticket, status: true),
                    ),
                  ],
                ),
              ),
              for (final reply in ticket['replies'])
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(reply['message']),
                      const SizedBox(height: 8),
                      Text(
                        mailStatusNames[reply['mail']?['status']] ??
                            'Chưa có thông tin gửi thư',
                        style: T.small,
                      ),
                    ],
                  ),
                ),
              if (ticket['status'] == 'CLOSED' && !pending)
                const Text('Mở lại yêu cầu để gửi câu trả lời mới.')
              else
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (pending)
                        const Text(
                          'Kết quả lần gửi trước chưa rõ. Gửi lại giữ nguyên nội dung và mã trả lời.',
                        ),
                      TextFormField(
                        controller: message,
                        maxLength: 3000,
                        maxLines: 5,
                        readOnly: busy || pending || needsReload,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung trả lời',
                        ),
                        validator: (v) => (v ?? '').trim().length >= 3
                            ? null
                            : 'Nhập từ 3 đến 3000 ký tự.',
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        pending ? 'Gửi lại cùng trả lời' : 'Lưu và gửi trả lời',
                        busy: busy,
                        onPressed: needsReload || value.isLoading
                            ? null
                            : () => change(ticket),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class RemoteMailPage extends ConsumerWidget {
  const RemoteMailPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminHeading(
        'Theo dõi thư',
        'Thư đơn hàng và phản hồi hỗ trợ được giữ trong hộp thư local.',
        actions: [
          AppButton(
            'Tải lại',
            outlined: true,
            onPressed: () => ref.invalidate(adminMailProvider),
          ),
        ],
      ),
      AdminAsync(
        value: ref.watch(adminMailProvider),
        reload: () => ref.invalidate(adminMailProvider),
        builder: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              data['enabled']
                  ? 'Gửi thư local đã bật.'
                  : 'Gửi thư đang tắt. Các thư đã lưu sẽ chờ đến khi dịch vụ được bật.',
            ),
            const SizedBox(height: 12),
            const SelectableText('Hộp thư trên máy này: http://127.0.0.1:8025'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                for (final s in mailStatusNames.entries)
                  Text('${s.value}: ${data['counts'][s.key] ?? 0}'),
              ],
            ),
            const SizedBox(height: 24),
            const Text('50 thư gần nhất', style: T.small),
            const SizedBox(height: 12),
            for (final row in data['items'])
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['subject'],
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SelectableText(row['recipient']),
                    const SizedBox(height: 8),
                    Text(
                      mailStatusNames[row['status']] ?? 'Không rõ trạng thái',
                    ),
                    Text('Số lần gửi: ${row['attempts']}', style: T.small),
                    if (row['status'] == 'FAILED')
                      const Text(
                        'Kiểm tra hộp thư và dịch vụ gửi thư local. Thư này vẫn được lưu để đối chiếu.',
                        style: T.small,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
