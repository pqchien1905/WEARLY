import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/account_state.dart';
import '../../../app/api_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_operations.dart';
import 'admin_widgets.dart';

final operationsSnapshotProvider =
    FutureProvider.autoDispose<OperationsSnapshot>((ref) {
      final account = ref.watch(
        adminAccountProvider.select((u) => (u?.id, u?.role)),
      );
      if (!ref.watch(remoteApiProvider) ||
          account.$1 == null ||
          account.$2 != 'ADMIN') {
        throw const ApiException(
          'FORBIDDEN',
          'Tài khoản chưa có quyền truy cập.',
          status: 403,
        );
      }
      return OperationsRepository(ref.watch(adminApiClientProvider)).snapshot();
    }, retry: (_, _) => null);
String _utc(DateTime? value) => value == null
    ? 'Chưa xác định'
    : '${value.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ')} UTC';
String _state(String value) => switch (value) {
  'ok' => 'Kết nối được',
  'disabled' => 'Tắt',
  _ => 'Chưa kết nối',
};

class RemoteOperationsPage extends ConsumerWidget {
  const RemoteOperationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void reload() => ref.invalidate(operationsSnapshotProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Vận hành & AI',
          'Theo dõi dịch vụ local và công việc đang chờ xử lý.',
          actions: [
            AppButton('Tải lại số liệu', outlined: true, onPressed: reload),
          ],
        ),
        AdminAsync(
          value: ref.watch(operationsSnapshotProvider),
          reload: reload,
          builder: (data) => _Snapshot(data),
        ),
      ],
    );
  }
}

class _Snapshot extends StatelessWidget {
  static final _title = T.body.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  const _Snapshot(this.data);
  final OperationsSnapshot data;
  @override
  Widget build(BuildContext context) {
    final work = data.work;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lần kiểm tra: ${_utc(data.observedAt)}', style: T.small),
        const SizedBox(height: 16),
        if (!data.workerLive)
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Không có tín hiệu worker gần đây', style: _title),
                const SizedBox(height: 8),
                const Text(
                  'Công việc có thể đang chờ. Kiểm tra tiến trình worker và Redis, rồi tải lại số liệu. Không gửi lại yêu cầu AI khi chưa biết kết quả cũ.',
                ),
                Text(
                  'Tín hiệu cuối: ${_utc(data.lastHeartbeat)}',
                  style: T.small,
                ),
              ],
            ),
          ),
        _grid([
          _service(
            'Cơ sở dữ liệu',
            data.databaseState,
            data.schemaReady == true
                ? 'Đã đủ cấu trúc · ${data.migrations ?? '—'} migration'
                : data.schemaReady == false
                ? 'Cấu trúc chưa đầy đủ. Kiểm tra migration trước khi vận hành.'
                : 'Không đọc được cấu trúc dữ liệu.',
          ),
          _service(
            'Redis / hàng đợi',
            data.redisState,
            'Kết nối hàng đợi được kiểm tra riêng với worker.',
          ),
          _service(
            'Kho ảnh riêng tư',
            data.storageState,
            'Kiểm tra quyền truy cập bucket, không đọc ảnh khách hàng.',
          ),
          _service(
            'Email SMTP',
            data.mailState,
            data.mailState == 'disabled'
                ? 'Chưa bật gửi thư.'
                : 'Chỉ kiểm tra kết nối SMTP; trạng thái gửi nằm trong công việc email.',
          ),
        ]),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Worker & hàng đợi', style: _title),
              const SizedBox(height: 10),
              Text(
                data.workerLive
                    ? 'Worker có tín hiệu trong 30 giây gần đây.'
                    : 'Worker chưa xác định.',
              ),
              const Text(
                'Tín hiệu hoạt động không xác nhận công việc đã hoàn tất.',
              ),
              const SizedBox(height: 16),
              _queue('Thử đồ AI', data.tryOnQueue),
              const SizedBox(height: 16),
              if (data.redisState != 'ok')
                const Text('Khôi phục mật khẩu: Chưa có số liệu.')
              else if (data.recoveryQueue == null)
                const Text('Khôi phục mật khẩu: Tắt')
              else
                _queue('Khôi phục mật khẩu', data.recoveryQueue),
            ],
          ),
        ),
        if (work == null)
          const AdminCard(child: Text('Chưa có số liệu công việc.'))
        else ...[
          _grid([
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ước tính chi phí AI hôm nay', style: _title),
                  const SizedBox(height: 12),
                  Text(
                    operationsMoney(work.estimatedVnd),
                    style: T.display(30),
                  ),
                  Text('${work.todayCount} yêu cầu đã được nhận'),
                  const SizedBox(height: 8),
                  const Text(
                    'Ước tính theo cấu hình, không phải hóa đơn Gemini. Bao gồm yêu cầu thất bại hoặc chưa rõ kết quả.',
                  ),
                  Text('Từ ${_utc(work.dayStartedAt)}', style: T.small),
                ],
              ),
            ),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tiến độ AI', style: _title),
                  const SizedBox(height: 12),
                  Text('Đã giữ hạn mức: ${work.reserved}'),
                  Text('Đang xử lý: ${work.processing}'),
                  Text('Quá hạn xử lý: ${work.stale}'),
                  Text('Chờ đưa vào hàng đợi: ${work.outboxPending}'),
                  Text(
                    'Chờ lâu nhất từ: ${_utc(work.outboxOldest)}',
                    style: T.small,
                  ),
                ],
              ),
            ),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Công việc email', style: _title),
                  const SizedBox(height: 12),
                  Text('Đang chờ: ${work.mailPending}'),
                  Text('Đang gửi: ${work.mailProcessing}'),
                  Text('Gửi thất bại: ${work.mailFailed}'),
                  const Text(
                    'Xem “Theo dõi thư” để kiểm tra từng lần gửi.',
                    style: T.small,
                  ),
                ],
              ),
            ),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dọn ảnh riêng tư', style: _title),
                  const SizedBox(height: 12),
                  Text('Ảnh chờ dọn: ${work.imagesPending}'),
                  const Text(
                    'Gồm ảnh đã xóa, hết hạn hoặc đang chờ thử dọn lại. Việc dọn chạy trong worker.',
                    style: T.small,
                  ),
                ],
              ),
            ),
          ]),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lỗi AI trong 24 giờ', style: _title),
                const SizedBox(height: 8),
                Text('Từ ${_utc(work.failuresSinceAt)}', style: T.small),
                if (work.failures.isEmpty)
                  const Text('Không ghi nhận lỗi trong khoảng này.')
                else
                  for (final failure in work.failures)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${failure.kind == 'TRY_ON'
                            ? 'Thử đồ'
                            : failure.kind == 'STYLIST'
                            ? 'Stylist'
                            : 'Khác'} · ${failure.code} · ${failure.count} lần',
                      ),
                    ),
                const SizedBox(height: 10),
                const Text(
                  'Đối chiếu kết quả trước khi tạo yêu cầu mới. Các yêu cầu không rõ kết quả có thể đã phát sinh phí.',
                  style: T.small,
                ),
              ],
            ),
          ),
        ],
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tích hợp', style: _title),
              const SizedBox(height: 12),
              Text(
                'Gemini: ${data.geminiConfigured ? 'Đã cấu hình' : 'Chưa cấu hình'}',
              ),
              Text('Stylist: ${data.stylistModel}', style: T.small),
              Text('Thử đồ: ${data.tryOnModel}', style: T.small),
              const SizedBox(height: 12),
              Text(
                'VNPay sandbox: ${data.vnpayConfigured ? 'Đã bật' : 'Chưa cấu hình'}',
              ),
              const Text('Vận chuyển: Mô phỏng local'),
              const SizedBox(height: 12),
              const Text(
                'Trạng thái cấu hình không xác nhận khóa hợp lệ hoặc dịch vụ bên ngoài đang hoạt động. Khóa được thiết lập ở backend/.env.',
                style: T.small,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _service(String title, String state, String detail) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _title),
        const SizedBox(height: 8),
        Text(
          _state(state),
          style: T.body.copyWith(
            color: state == 'ok' ? T.accent : T.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(detail, style: T.small),
      ],
    ),
  );
  Widget _queue(String title, OperationsQueue? queue) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: T.body.copyWith(fontWeight: FontWeight.w600)),
      if (queue == null)
        const Text('Chưa có số liệu.')
      else ...[
        Text('Đang chờ: ${queue.waiting} · Đang chạy: ${queue.active}'),
        Text(
          'Hẹn xử lý: ${queue.delayed} · Lỗi lưu trong hàng đợi: ${queue.failed}',
        ),
        Text('Chờ lâu nhất từ: ${_utc(queue.oldestWaitingAt)}', style: T.small),
      ],
    ],
  );
  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 16,
      children: [
        for (final child in children)
          SizedBox(
            width: constraints.maxWidth < 700
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 2,
            child: child,
          ),
      ],
    ),
  );
}
