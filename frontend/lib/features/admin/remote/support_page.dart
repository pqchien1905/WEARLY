export 'mail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/support_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_support.dart';
import '../../../data/remote_admin.dart';
import 'admin_pagination.dart';
import 'admin_widgets.dart';
import 'admin_providers.dart' show staffRoleProvider, canStaff;
import 'admin_presentation.dart';
import 'operations_widgets.dart';

class RemoteSupportPage extends ConsumerStatefulWidget {
  const RemoteSupportPage({super.key});
  @override
  ConsumerState<RemoteSupportPage> createState() => _RemoteSupportPageState();
}

class _RemoteSupportPageState extends ConsumerState<RemoteSupportPage> {
  int page = 1, limit = 10;
  String? status;
  @override
  Widget build(BuildContext context) {
    final provider = supportInboxProvider((
      page: page,
      limit: limit,
      status: status,
    ));
    final value = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Hỗ trợ khách hàng',
          'Tiếp nhận yêu cầu, theo dõi phản hồi và chăm sóc khách hàng.',
          actions: [
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              busy: value.isLoading,
              onPressed: () => ref.invalidate(provider),
            ),
            if (canStaff(ref.watch(staffRoleProvider), 'mail.read'))
              AppButton(
                'Theo dõi thư',
                outlined: true,
                icon: Icons.mail_outline,
                onPressed: () => context.go('/admin/mail'),
              ),
          ],
        ),
        OperationsPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Hộp thư hỗ trợ'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in <String?, String>{
                    null: 'Tất cả yêu cầu',
                    ...supportStatusNames,
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: status == entry.key,
                      onSelected: value.isLoading
                          ? null
                          : (_) => setState(() {
                              status = entry.key;
                              page = 1;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              AdminAsync(
                value: value,
                reload: () => ref.invalidate(provider),
                builder: (data) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '${adminNumber(data['total'])} yêu cầu${status == null ? '' : ' · ${supportStatusNames[status]}'} · Mới nhất trước',
                        style: T.small,
                      ),
                    ),
                    if ((data['items'] as List).isEmpty)
                      OperationsEmpty(
                        title: status == null
                            ? 'Chưa có yêu cầu hỗ trợ.'
                            : 'Không có yêu cầu ở trạng thái này',
                        message: status == null
                            ? 'Yêu cầu của khách hàng sẽ xuất hiện tại đây.'
                            : 'Chọn trạng thái khác để xem các yêu cầu còn lại.',
                        icon: Icons.support_agent_outlined,
                      )
                    else
                      OperationsTable(
                        headers: const [
                          'Khách hàng',
                          'Trạng thái',
                          'Ngày tiếp nhận',
                          'Thao tác',
                        ],
                        widths: const [3.2, 1.8, 2, 1.8],
                        rows: [
                          for (final row in data['items'])
                            [
                              OperationsIdentity(
                                name: row['name'],
                                email: row['email'],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  supportStatus(row['status']),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${row['_count']?['replies'] ?? 0} phản hồi',
                                    style: T.small,
                                  ),
                                ],
                              ),
                              Text(adminDate(row['createdAt']), style: T.small),
                              _openTicket(context, row['id']),
                            ],
                        ],
                        cards: [
                          for (final row in data['items'])
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OperationsIdentity(
                                  name: row['name'],
                                  email: row['email'],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    supportStatus(row['status']),
                                    Text(
                                      '${row['_count']?['replies'] ?? 0} phản hồi',
                                      style: T.small,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tiếp nhận: ${adminDate(row['createdAt'])}',
                                  style: T.small,
                                ),
                                const SizedBox(height: 8),
                                _openTicket(context, row['id']),
                              ],
                            ),
                        ],
                      ),
                    AdminPagination(
                      page: AdminPage(data),
                      loading: value.isLoading,
                      onPage: (n) => setState(() => page = n),
                      onPageSize: (n) => setState(() {
                        limit = n;
                        page = 1;
                      }),
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

  Widget _openTicket(BuildContext context, String id) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => context.go('/admin/support/$id'),
      icon: const Icon(Icons.arrow_forward, size: 16),
      iconAlignment: IconAlignment.end,
      label: const Text('Xem và trả lời'),
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.standard,
      ),
    ),
  );
}

Widget supportStatus(String status) => AdminStatus(
  supportStatusNames[status] ?? 'Không rõ trạng thái',
  color: switch (status) {
    'OPEN' => T.warning,
    'ANSWERED' => T.success,
    _ => T.muted,
  },
);

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
      ref.invalidate(supportPagesProvider);
      ref.invalidate(supportInboxProvider);
      ref.invalidate(adminMailPagesProvider);
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
          'Trả lời được lưu trước khi gửi tới email của khách hàng.',
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
