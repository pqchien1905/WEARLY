import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../data/remote_operations.dart';
import 'admin_presentation.dart';
import 'operations_widgets.dart';

String _utc(DateTime? value) => value == null
    ? 'Chưa xác định'
    : '${value.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ')} UTC';

class OperationsSnapshotView extends StatelessWidget {
  const OperationsSnapshotView(this.data, {super.key});
  final OperationsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final work = data.work;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!data.workerLive) ...[
          OperationsNotice(
            title: 'Không có tín hiệu worker gần đây',
            message:
                'Công việc có thể đang chờ. Kiểm tra worker và Redis trước khi gửi lại yêu cầu AI. Tín hiệu cuối: ${_utc(data.lastHeartbeat)}.',
            icon: Icons.warning_amber_rounded,
            color: T.warning,
          ),
          const SizedBox(height: 24),
        ],
        AdminSectionTitle(
          'Tình trạng dịch vụ',
          action: Text(
            'Lần kiểm tra: ${_utc(data.observedAt)}',
            style: T.small,
          ),
        ),
        OperationsGrid(
          compactMinWidth: 150,
          children: [
            _service(
              'Cơ sở dữ liệu',
              Icons.dns_outlined,
              data.databaseState,
              data.schemaReady == true
                  ? 'Đã đủ cấu trúc · ${data.migrations ?? '—'} migration'
                  : data.schemaReady == false
                  ? 'Cấu trúc chưa đầy đủ. Kiểm tra migration trước khi vận hành.'
                  : 'Không đọc được cấu trúc dữ liệu.',
              needsAttention:
                  data.databaseState == 'ok' && data.schemaReady != true,
            ),
            _service(
              'Redis / hàng đợi',
              Icons.storage_outlined,
              data.redisState,
              'Tiếp nhận và phân phối công việc cho worker.',
            ),
            _service(
              'Kho ảnh riêng tư',
              Icons.cloud_outlined,
              data.storageState,
              'Kiểm tra quyền truy cập kho ảnh, không đọc ảnh khách hàng.',
            ),
            _service(
              'Email SMTP',
              Icons.mail_outline,
              data.mailState,
              data.mailState == 'disabled'
                  ? 'Chưa bật gửi thư.'
                  : 'Kết nối máy chủ gửi thư. Kết quả từng thư được theo dõi riêng.',
            ),
          ],
        ),
        const SizedBox(height: 28),
        const AdminSectionTitle('Hoạt động & công việc'),
        if (work == null)
          const OperationsPanel(
            child: OperationsEmpty(
              title: 'Chưa có số liệu công việc.',
              message:
                  'Khôi phục kết nối cơ sở dữ liệu rồi tải lại để xem số liệu.',
              icon: Icons.query_stats,
            ),
          )
        else ...[
          OperationsGrid(
            compactMinWidth: 150,
            children: [
              OperationsMetric(
                label: 'Ước tính chi phí AI hôm nay',
                value: operationsMoney(work.estimatedVnd),
                icon: Icons.auto_awesome_outlined,
                caption: '${work.todayCount} yêu cầu đã được nhận',
              ),
              OperationsMetric(
                label: 'AI đang xử lý',
                value: adminNumber(work.processing),
                icon: Icons.timelapse,
                caption: '${work.stale} yêu cầu quá hạn',
                color: work.stale > 0 ? T.warning : T.accent,
              ),
              OperationsMetric(
                label: 'Thư chờ gửi',
                value: adminNumber(work.mailPending),
                icon: Icons.outgoing_mail,
                caption:
                    '${work.mailProcessing} đang gửi · ${work.mailFailed} thất bại',
                color: work.mailFailed > 0 ? T.danger : T.accent,
              ),
              OperationsMetric(
                label: 'Ảnh chờ dọn',
                value: adminNumber(work.imagesPending),
                icon: Icons.auto_delete_outlined,
                caption: 'Ảnh đã xóa hoặc hết hạn',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Chi phí ước tính theo cấu hình từ ${_utc(work.dayStartedAt)}, không phải hóa đơn Gemini. Bao gồm yêu cầu thất bại hoặc chưa rõ kết quả.',
            style: T.small,
          ),
        ],
        const SizedBox(height: 24),
        OperationsGrid(
          minWidth: 400,
          maxColumns: 2,
          children: [
            OperationsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminSectionTitle(
                    'Worker & hàng đợi',
                    action: AdminStatus(
                      data.workerLive ? 'Có tín hiệu' : 'Chưa xác định',
                      color: data.workerLive ? T.success : T.warning,
                    ),
                  ),
                  Text(
                    data.workerLive
                        ? 'Worker có tín hiệu trong 30 giây gần đây.'
                        : 'Worker chưa xác định.',
                    style: T.small,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tín hiệu hoạt động không xác nhận công việc đã hoàn tất.',
                    style: T.small,
                  ),
                  const Divider(height: 32),
                  _queue('Thử đồ AI', data.tryOnQueue),
                  const Divider(height: 32),
                  if (data.redisState != 'ok')
                    const Text(
                      'Khôi phục mật khẩu: Chưa có số liệu.',
                      style: T.small,
                    )
                  else if (data.recoveryQueue == null)
                    const Text('Khôi phục mật khẩu: Tắt', style: T.small)
                  else
                    _queue('Khôi phục mật khẩu', data.recoveryQueue),
                ],
              ),
            ),
            OperationsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AdminSectionTitle('Tiến độ AI'),
                  if (work == null)
                    const Text('Chưa có số liệu.', style: T.small)
                  else ...[
                    _count('Đã giữ hạn mức', work.reserved),
                    _count('Đang xử lý', work.processing),
                    _count(
                      'Quá hạn xử lý',
                      work.stale,
                      color: work.stale > 0 ? T.danger : T.muted,
                    ),
                    _count('Chờ đưa vào hàng đợi', work.outboxPending),
                    const SizedBox(height: 12),
                    Text(
                      'Chờ lâu nhất từ: ${_utc(work.outboxOldest)}',
                      style: T.small,
                    ),
                    const Divider(height: 32),
                    Text(
                      'Dọn ảnh riêng tư',
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${work.imagesPending} ảnh đã xóa, hết hạn hoặc chờ thử dọn lại. Việc dọn chạy trong worker.',
                      style: T.small,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (work != null) ...[
          OperationsGrid(
            minWidth: 400,
            maxColumns: 2,
            children: [
              OperationsPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminSectionTitle('Lỗi AI trong 24 giờ'),
                    Text('Từ ${_utc(work.failuresSinceAt)}', style: T.small),
                    const SizedBox(height: 16),
                    if (work.failures.isEmpty)
                      const OperationsNotice(
                        title: 'Không ghi nhận lỗi trong khoảng này.',
                        message:
                            'Các lỗi mới sẽ được tổng hợp khi tải lại số liệu.',
                        icon: Icons.check_circle_outline,
                        color: T.success,
                      )
                    else
                      for (final failure in work.failures)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: T.danger,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      failure.kind == 'TRY_ON'
                                          ? 'Thử đồ AI'
                                          : failure.kind == 'STYLIST'
                                          ? 'Stylist'
                                          : 'Khác',
                                      style: T.body.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(failure.code, style: T.small),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              AdminStatus(
                                '${failure.count} lần',
                                color: T.danger,
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 12),
                    const Text(
                      'Đối chiếu kết quả trước khi tạo yêu cầu mới. Yêu cầu chưa rõ kết quả có thể đã phát sinh phí.',
                      style: T.small,
                    ),
                  ],
                ),
              ),
              OperationsPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminSectionTitle('Công việc email'),
                    _count('Đang chờ', work.mailPending),
                    _count('Đang gửi', work.mailProcessing),
                    _count(
                      'Gửi thất bại',
                      work.mailFailed,
                      color: work.mailFailed > 0 ? T.danger : T.muted,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.go('/admin/mail'),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        iconAlignment: IconAlignment.end,
                        label: const Text('Theo dõi thư'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        OperationsPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Tích hợp'),
              OperationsGrid(
                minWidth: 280,
                maxColumns: 3,
                children: [
                  _integration(
                    'Gemini AI',
                    data.geminiConfigured ? 'Đã cấu hình' : 'Chưa cấu hình',
                    'Stylist: ${data.stylistModel}\nThử đồ: ${data.tryOnModel}',
                    data.geminiConfigured,
                  ),
                  _integration(
                    'VNPay sandbox',
                    data.vnpayConfigured ? 'Đã bật' : 'Chưa cấu hình',
                    'Môi trường thử nghiệm thanh toán.',
                    data.vnpayConfigured,
                  ),
                  _integration(
                    'MoMo sandbox',
                    data.momoConfigured ? 'Đã bật' : 'Chưa cấu hình',
                    'Ví điện tử MoMo, môi trường thử nghiệm.',
                    data.momoConfigured,
                  ),
                  _integration(
                    'ZaloPay sandbox',
                    data.zalopayConfigured ? 'Đã bật' : 'Chưa cấu hình',
                    'Ví điện tử ZaloPay, môi trường thử nghiệm.',
                    data.zalopayConfigured,
                  ),
                  _integration(
                    'Vận chuyển',
                    'Mô phỏng local',
                    'Theo dõi quy trình giao hàng thử nghiệm.',
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Trạng thái cấu hình không xác nhận khóa hợp lệ hoặc dịch vụ bên ngoài đang hoạt động.',
                style: T.small,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _service(
    String title,
    IconData icon,
    String state,
    String detail, {
    bool needsAttention = false,
  }) {
    final color = state == 'ok' && !needsAttention
        ? T.success
        : state == 'disabled'
        ? T.muted
        : T.warning;
    return OperationsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: T.radius,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 16),
          Text(title, style: T.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          AdminStatus(
            needsAttention
                ? 'Cần kiểm tra cấu trúc'
                : switch (state) {
                    'ok' => 'Kết nối được',
                    'disabled' => 'Tắt',
                    _ => 'Chưa kết nối',
                  },
            color: color,
          ),
          const SizedBox(height: 12),
          Text(detail, style: T.small),
        ],
      ),
    );
  }

  Widget _queue(String title, OperationsQueue? queue) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: T.body.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      if (queue == null)
        const Text('Chưa có số liệu.', style: T.small)
      else ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AdminStatus('Đang chờ: ${queue.waiting}', color: T.warning),
            AdminStatus('Đang chạy: ${queue.active}', color: T.accent),
            AdminStatus('Hẹn xử lý: ${queue.delayed}'),
            AdminStatus(
              'Lỗi: ${queue.failed}',
              color: queue.failed > 0 ? T.danger : T.muted,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Chờ lâu nhất từ: ${_utc(queue.oldestWaitingAt)}', style: T.small),
      ],
    ],
  );

  Widget _count(String label, int count, {Color color = T.ink}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: T.body.copyWith(color: T.muted)),
        ),
        const SizedBox(width: 16),
        Text(
          adminNumber(count),
          style: T.body.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _integration(
    String title,
    String status,
    String detail,
    bool configured,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: T.body.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      AdminStatus(status, color: configured ? T.accent : T.muted),
      const SizedBox(height: 10),
      Text(detail, style: T.small),
    ],
  );
}
