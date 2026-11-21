import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/support_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_admin.dart';
import '../../../data/remote_support.dart';
import 'admin_pagination.dart';
import 'admin_presentation.dart';
import 'admin_widgets.dart';
import 'operations_widgets.dart';

class RemoteMailPage extends ConsumerStatefulWidget {
  const RemoteMailPage({super.key});
  @override
  ConsumerState<RemoteMailPage> createState() => _RemoteMailPageState();
}

class _RemoteMailPageState extends ConsumerState<RemoteMailPage> {
  int page = 1, limit = 10;
  @override
  Widget build(BuildContext context) {
    final provider = adminMailPagesProvider((page: page, limit: limit));
    final value = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Theo dõi thư',
          'Kiểm tra thư đơn hàng, phản hồi hỗ trợ và kết quả gửi tới khách hàng.',
          actions: [
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              busy: value.isLoading,
              onPressed: () => ref.invalidate(provider),
            ),
          ],
        ),
        AdminAsync(
          value: value,
          reload: () => ref.invalidate(provider),
          builder: (data) {
            final enabled = data['enabled'] == true;
            final local = data['delivery'] == 'local';
            final rows = (data['items'] as List).cast<Map<String, dynamic>>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OperationsGrid(
                  compactMinWidth: 150,
                  children: [
                    for (final (status, label, icon, color) in const [
                      ('PENDING', 'Chờ gửi thư', Icons.schedule, T.warning),
                      (
                        'PROCESSING',
                        'Đang gửi thư',
                        Icons.outgoing_mail,
                        T.accent,
                      ),
                      (
                        'SENT',
                        'Đã gửi thư',
                        Icons.mark_email_read_outlined,
                        T.success,
                      ),
                      (
                        'FAILED',
                        'Gửi thư thất bại',
                        Icons.error_outline,
                        T.danger,
                      ),
                    ])
                      OperationsMetric(
                        label: label,
                        value: adminNumber(data['counts']?[status] ?? 0),
                        icon: icon,
                        color: color,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                OperationsNotice(
                  title: !enabled
                      ? 'Dịch vụ gửi thư đang tắt'
                      : local
                      ? 'Đang dùng hộp thư thử nghiệm'
                      : 'Dịch vụ gửi thư đã bật',
                  message: !enabled
                      ? 'Thư đã lưu sẽ chờ xử lý khi dịch vụ được bật trở lại.'
                      : local
                      ? 'Thư được chuyển tới hộp thư trên máy này để kiểm tra.'
                      : 'Thư được gửi qua máy chủ SMTP. Theo dõi kết quả của từng thư trong danh sách bên dưới.',
                  icon: enabled
                      ? Icons.mark_email_read_outlined
                      : Icons.pause_circle_outline,
                  color: enabled && !local ? T.success : T.warning,
                ),
                if (enabled && local)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SelectableText(
                      'Hộp thư trên máy này: http://127.0.0.1:8025',
                      style: T.small,
                    ),
                  ),
                const SizedBox(height: 24),
                OperationsPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminSectionTitle(
                        'Lịch sử gửi thư',
                        action: Text(
                          '${adminNumber(data['total'])} thư · Mới nhất trước',
                          style: T.small,
                        ),
                      ),
                      if (rows.isEmpty)
                        const OperationsEmpty(
                          title: 'Chưa có thư nào',
                          message:
                              'Thư xác nhận đơn hàng và phản hồi hỗ trợ sẽ được theo dõi tại đây.',
                          icon: Icons.mail_outline,
                        )
                      else
                        OperationsTable(
                          headers: const [
                            'Nội dung thư',
                            'Người nhận',
                            'Trạng thái',
                            'Thời gian',
                          ],
                          widths: const [3.2, 2.6, 1.8, 2],
                          rows: [
                            for (final row in rows)
                              [
                                _subject(row),
                                SelectableText(
                                  '${row['recipient']}',
                                  style: T.body.copyWith(fontSize: 13),
                                ),
                                _status(row),
                                _date(row),
                              ],
                          ],
                          cards: [
                            for (final row in rows)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _subject(row),
                                  const SizedBox(height: 12),
                                  SelectableText(
                                    'Đến: ${row['recipient']}',
                                    style: T.small,
                                  ),
                                  const SizedBox(height: 12),
                                  _status(row),
                                  const SizedBox(height: 8),
                                  _date(row),
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
            );
          },
        ),
      ],
    );
  }

  Widget _subject(Map<String, dynamic> row) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${row['subject']}',
        style: T.body.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(
            row['supportId'] != null
                ? Icons.support_agent_outlined
                : row['orderId'] != null
                ? Icons.receipt_long_outlined
                : Icons.mail_outline,
            size: 14,
            color: T.muted,
          ),
          const SizedBox(width: 6),
          Text(
            row['supportId'] != null
                ? 'Hỗ trợ khách hàng'
                : row['orderId'] != null
                ? 'Đơn hàng'
                : 'Thông báo',
            style: T.small,
          ),
        ],
      ),
    ],
  );

  Widget _status(Map<String, dynamic> row) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminStatus(
        mailStatusNames[row['status']] ?? 'Không rõ trạng thái',
        color: switch (row['status']) {
          'SENT' => T.success,
          'FAILED' => T.danger,
          'PENDING' => T.warning,
          _ => T.accent,
        },
      ),
      const SizedBox(height: 6),
      Text('Số lần gửi: ${row['attempts']}', style: T.small),
      if (row['status'] == 'FAILED') ...[
        const SizedBox(height: 4),
        const Text('Cần kiểm tra dịch vụ gửi thư.', style: T.small),
      ],
    ],
  );

  Widget _date(Map<String, dynamic> row) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Tạo: ${adminDate(row['createdAt'])}', style: T.small),
      if (row['sentAt'] != null) ...[
        const SizedBox(height: 4),
        Text('Gửi: ${adminDate(row['sentAt'])}', style: T.small),
      ],
    ],
  );
}
