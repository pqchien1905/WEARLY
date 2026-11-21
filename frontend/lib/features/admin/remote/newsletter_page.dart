import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../app/api_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';

final newsletterPageProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>(
      (ref, page) async => Map<String, dynamic>.from(
        await ref
                .watch(adminApiClientProvider)
                .get(
                  'admin/newsletter',
                  query: {'page': '$page', 'limit': '20'},
                )
            as Map,
      ),
    );
final newsletterCampaignsProvider = FutureProvider.autoDispose<List>(
  (ref) async =>
      await ref.watch(adminApiClientProvider).get('admin/newsletter/campaigns')
          as List,
);

class RemoteNewsletterPage extends ConsumerStatefulWidget {
  const RemoteNewsletterPage({super.key});
  @override
  ConsumerState<RemoteNewsletterPage> createState() =>
      _RemoteNewsletterPageState();
}

class _RemoteNewsletterPageState extends ConsumerState<RemoteNewsletterPage> {
  final subject = TextEditingController(), body = TextEditingController();
  final form = GlobalKey<FormState>();
  String requestKey = const Uuid().v4();
  int page = 1;
  bool busy = false;
  String? error;
  void refresh() {
    ref.invalidate(newsletterPageProvider);
    ref.invalidate(newsletterCampaignsProvider);
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> queue(Map row) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xếp lịch gửi bản tin'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['subject']}', style: T.body),
                const SizedBox(height: 12),
                Text('${row['body']}'),
                const SizedBox(height: 20),
                const Text(
                  'Gửi đến những người đang đồng ý nhận tin. Mỗi thư có đường dẫn hủy đăng ký. Thư sẽ chờ nếu dịch vụ gửi đang tắt.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận xếp hàng gửi'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      await ref
          .read(adminApiClientProvider)
          .request(
            'POST',
            'admin/newsletter/campaigns/${row['id']}/queue',
            body: {'expectedVersion': row['version']},
          );
    });
  }

  @override
  void dispose() {
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminHeading(
        'Bản tin',
        'Quản lý người đồng ý nhận tin và các chiến dịch gửi email.',
        actions: [
          AppButton(
            'Tải lại',
            outlined: true,
            onPressed: busy ? null : refresh,
          ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(error!, style: const TextStyle(color: T.danger)),
        ),
      AdminCard(
        child: AdminAsync(
          value: ref.watch(newsletterPageProvider(page)),
          reload: refresh,
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminSectionTitle(
                'Người đăng ký · ${data['active']} đang nhận tin',
              ),
              if ((data['items'] as List).isEmpty)
                const Text('Chưa có người đăng ký.'),
              for (final row in data['items'] as List)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row['email']}'),
                  subtitle: Text(
                    row['unsubscribedAt'] == null
                        ? 'Đang nhận tin'
                        : 'Đã hủy đăng ký',
                  ),
                  trailing: row['unsubscribedAt'] != null
                      ? null
                      : TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  await ref
                                      .read(adminApiClientProvider)
                                      .request(
                                        'POST',
                                        'admin/newsletter/subscriptions/${row['id']}/unsubscribe',
                                      );
                                }),
                          child: const Text('Ngừng gửi'),
                        ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: page > 1 && !busy
                        ? () => setState(() => page--)
                        : null,
                    child: const Text('Trang trước'),
                  ),
                  Text('Trang $page'),
                  TextButton(
                    onPressed: page * 20 < (data['total'] as int) && !busy
                        ? () => setState(() => page++)
                        : null,
                    child: const Text('Trang sau'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      AdminCard(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Soạn bản nháp'),
              TextFormField(
                controller: subject,
                maxLength: 200,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Tiêu đề'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Nhập tiêu đề.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: body,
                maxLength: 10000,
                minLines: 5,
                maxLines: 12,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Nội dung'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Nhập nội dung.' : null,
              ),
              AppButton(
                'Lưu bản nháp',
                busy: busy,
                onPressed: busy
                    ? null
                    : () {
                        if (!form.currentState!.validate()) return;
                        run(() async {
                          await ref
                              .read(adminApiClientProvider)
                              .request(
                                'POST',
                                'admin/newsletter/campaigns',
                                body: {
                                  'requestKey': requestKey,
                                  'subject': subject.text.trim(),
                                  'body': body.text.trim(),
                                },
                              );
                          if (mounted) {
                            subject.clear();
                            body.clear();
                            requestKey = const Uuid().v4();
                          }
                        });
                      },
              ),
            ],
          ),
        ),
      ),
      AdminCard(
        child: AdminAsync(
          value: ref.watch(newsletterCampaignsProvider),
          reload: refresh,
          builder: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Chiến dịch gần đây'),
              if (rows.isEmpty) const Text('Chưa có chiến dịch.'),
              for (final row in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row['subject']}'),
                  subtitle: Text(
                    row['queuedAt'] == null
                        ? 'Bản nháp · chưa gửi'
                        : 'Đã xếp hàng ${row['recipientCount']} thư · xem kết quả trong Theo dõi thư',
                  ),
                  trailing: row['queuedAt'] != null
                      ? null
                      : TextButton(
                          onPressed: busy ? null : () => queue(row as Map),
                          child: const Text('Xem và gửi'),
                        ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
