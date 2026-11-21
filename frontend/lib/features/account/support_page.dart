import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/api_providers.dart';
import '../../app/support_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_support.dart';
import 'account_components.dart';
import 'account_navigation.dart';

String _date(Object? value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

Color _statusColor(Object? status) => switch (status) {
  'ANSWERED' => T.success,
  'CLOSED' => T.muted,
  _ => T.warning,
};

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final Object? status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _statusColor(status).withValues(alpha: .1),
      borderRadius: T.radius,
    ),
    child: Text(
      supportStatusNames[status] ?? '$status',
      style: T.small.copyWith(color: _statusColor(status)),
    ),
  );
}

/// The signed-in customer's support requests (`/account/support`).
class SupportRequestsPage extends ConsumerStatefulWidget {
  const SupportRequestsPage({super.key, this.id});
  final String? id;
  @override
  ConsumerState<SupportRequestsPage> createState() =>
      _SupportRequestsPageState();
}

class _SupportRequestsPageState extends ConsumerState<SupportRequestsPage> {
  int page = 1;
  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    return AccountFrame(
      title: 'Hỗ trợ',
      current: '/account/support',
      child: !remote
          ? const StatePanel(
              title: 'Hỗ trợ cần cửa hàng trực tuyến',
              message:
                  'Đăng nhập trong cửa hàng trực tuyến để xem các yêu cầu hỗ trợ của bạn.',
            )
          : widget.id != null
          ? _SupportThread(key: ValueKey(widget.id), id: widget.id!)
          : _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final value = ref.watch(mySupportProvider(page));
    return AccountCard(
      title: 'Yêu cầu hỗ trợ của bạn',
      description:
          'Các yêu cầu gửi khi đã đăng nhập được lưu ở đây cùng câu trả lời của cửa hàng.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              'Gửi yêu cầu mới',
              icon: Icons.add_comment_outlined,
              onPressed: () => context.go('/contact'),
            ),
          ),
          const SizedBox(height: 16),
          value.when(
            skipLoadingOnRefresh: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => StatePanel(
              title: 'Chưa tải được yêu cầu hỗ trợ',
              message: e is ApiException ? e.message : 'Vui lòng thử lại.',
              action: AppButton(
                'Thử lại',
                onPressed: () => ref.invalidate(mySupportProvider(page)),
              ),
            ),
            data: (data) {
              final items = data['items'] as List;
              final total = data['total'] as int;
              final limit = data['limit'] as int? ?? 10;
              if (items.isEmpty && page == 1) {
                return const Text(
                  'Bạn chưa có yêu cầu hỗ trợ nào.',
                  style: T.body,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: T.line),
                        borderRadius: T.radius,
                      ),
                      child: ListTile(
                        onTap: () =>
                            context.go('/account/support/${row['id']}'),
                        title: Text(
                          '${row['message']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: T.body,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StatusChip(row['status']),
                              Text(_date(row['createdAt']), style: T.small),
                              Text(
                                '${row['_count']?['replies'] ?? 0} tin nhắn',
                                style: T.small,
                              ),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  if (page > 1 || page * limit < total)
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: page > 1
                              ? () => setState(() => page--)
                              : null,
                          child: const Text('Trang trước'),
                        ),
                        Text('Trang $page', style: T.small),
                        TextButton(
                          onPressed: page * limit < total
                              ? () => setState(() => page++)
                              : null,
                          child: const Text('Trang sau'),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SupportThread extends ConsumerStatefulWidget {
  const _SupportThread({super.key, required this.id});
  final String id;
  @override
  ConsumerState<_SupportThread> createState() => _SupportThreadState();
}

class _SupportThreadState extends ConsumerState<_SupportThread> {
  final form = GlobalKey<FormState>();
  final message = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    message.text =
        ref
                .read(supportRepositoryProvider)
                .pendingFollowUp(widget.id)?['message']
            as String? ??
        '';
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final repo = ref.read(supportRepositoryProvider);
    final pending = repo.pendingFollowUp(widget.id) != null;
    if (busy || (!pending && !form.currentState!.validate())) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.followUp(widget.id, message.text);
      if (!mounted) return;
      message.clear();
      ref.invalidate(mySupportDetailProvider(widget.id));
      ref.invalidate(mySupportProvider);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa xác nhận được kết quả. Hãy gửi lại cùng tin nhắn.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(mySupportDetailProvider(widget.id));
    final pending =
        ref.watch(supportRepositoryProvider).pendingFollowUp(widget.id) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/account/support'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Tất cả yêu cầu'),
          ),
        ),
        const SizedBox(height: 8),
        value.when(
          skipLoadingOnRefresh: true,
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => StatePanel(
            title: 'Không mở được yêu cầu này',
            message: e is ApiException && e.status == 404
                ? 'Yêu cầu không tồn tại hoặc không thuộc tài khoản của bạn.'
                : 'Vui lòng thử lại.',
            action: AppButton(
              'Thử lại',
              onPressed: () =>
                  ref.invalidate(mySupportDetailProvider(widget.id)),
            ),
          ),
          data: (ticket) {
            final closed = ticket['status'] == 'CLOSED';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusChip(ticket['status']),
                          Text(_date(ticket['createdAt']), style: T.small),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText('${ticket['message']}', style: T.body),
                      const SizedBox(height: 8),
                      SelectableText(
                        'Mã yêu cầu: ${ticket['id']}',
                        style: T.small,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final reply in ticket['replies'] as List)
                  _Message(reply: reply as Map),
                const SizedBox(height: 8),
                if (closed && !pending)
                  const Text(
                    'Yêu cầu đã đóng. Nếu cần hỗ trợ thêm, hãy gửi một yêu cầu mới.',
                    style: T.body,
                  )
                else
                  Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (pending)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Lần gửi trước chưa xác nhận được. Gửi lại giữ nguyên nội dung để tránh trùng.',
                              style: T.small,
                            ),
                          ),
                        TextFormField(
                          controller: message,
                          readOnly: busy || pending,
                          maxLength: 3000,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Nhắn thêm cho cửa hàng',
                          ),
                          validator: (v) => (v ?? '').trim().length >= 3
                              ? null
                              : 'Nhập từ 3 đến 3000 ký tự.',
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              error!,
                              style: const TextStyle(color: T.danger),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton(
                            pending ? 'Gửi lại tin nhắn' : 'Gửi tin nhắn',
                            busy: busy,
                            onPressed: send,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.reply});
  final Map reply;
  @override
  Widget build(BuildContext context) {
    final mine = reply['fromCustomer'] == true;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mine ? T.soft : T.surface,
            border: Border.all(color: T.line),
            borderRadius: T.radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mine ? 'Bạn' : 'Cửa hàng WEARLY',
                style: T.small.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SelectableText('${reply['message']}', style: T.body),
              const SizedBox(height: 6),
              Text(_date(reply['createdAt']), style: T.small),
            ],
          ),
        ),
      ),
    );
  }
}
