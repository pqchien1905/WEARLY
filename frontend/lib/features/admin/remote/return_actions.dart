import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/primitives.dart';
import '../../../core/format.dart';
import '../../../data/remote_returns.dart';
import '../../../domain/commerce.dart';
import '../../account/returns_panel.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

class AdminReturnActions extends ConsumerWidget {
  const AdminReturnActions({
    super.key,
    required this.data,
    required this.order,
  });
  final AdminRecord data;
  final Order order;
  Future<void> act(
    BuildContext context,
    WidgetRef ref,
    ReturnCase? request,
    String action,
    String title,
  ) async {
    final repo = ref.read(adminRepositoryProvider),
        note = TextEditingController();
    final cancellation = request == null;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminMutationDialog(
        title: title,
        reload: () => refreshAdmin(ref),
        onDisposed: note.dispose,
        message: cancellation
            ? 'Hủy trước khi gửi sẽ trả tồn kho và lượt khuyến mãi. Khoản đã thu giữ nguyên để xử lý hoàn tiền riêng.'
            : action == 'RECEIVED'
            ? 'Chỉ xác nhận sau khi nhận đủ số lượng đã duyệt. Kho sẽ được cộng lại; ${money(request.amount)} cần xử lý hoàn tiền riêng.'
            : 'Quyết định này và ghi chú sẽ hiển thị cho khách.',
        fields: [
          TextFormField(
            controller: note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: cancellation ? 'Lý do hủy đơn' : 'Ghi chú cho khách',
            ),
            validator: (v) =>
                (v ?? '').trim().length > 300 ||
                    (cancellation && (v ?? '').trim().length < 3)
                ? 'Nhập nội dung hợp lệ, tối đa 300 ký tự.'
                : null,
          ),
        ],
        submit: () async {
          if (cancellation) {
            await repo.cancelOrder(
              order.id,
              version: data['version'],
              reason: note.text.trim(),
            );
          } else {
            await repo.returnAction(
              order.id,
              request.id,
              version: request.version,
              action: action,
              note: note.text.trim(),
            );
          }
        },
      ),
    );
    if (context.mounted && changed == true) {
      refreshAdmin(ref);
      toast(
        context,
        cancellation
            ? 'Đã hủy đơn hàng và cập nhật lại tồn kho.'
            : 'Đã cập nhật yêu cầu trả hàng.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = (data['returns'] as List? ?? []).map(ReturnCase.new);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canStaff(ref.watch(staffRoleProvider), 'orders.cancel') &&
            ['PENDING', 'CONFIRMED'].contains(data['status']))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppButton(
              'Hủy đơn trước khi gửi',
              outlined: true,
              onPressed: () =>
                  act(context, ref, null, 'CANCEL', 'Hủy đơn trước khi gửi'),
            ),
          ),
        for (final request in requests)
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReturnHistory(request: request, order: order),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (canStaff(
                          ref.watch(staffRoleProvider),
                          'returns.decide',
                        ) &&
                        request.status == 'REQUESTED') ...[
                      AppButton(
                        'Duyệt trả hàng',
                        onPressed: () => act(
                          context,
                          ref,
                          request,
                          'APPROVED',
                          'Duyệt trả hàng',
                        ),
                      ),
                      AppButton(
                        'Từ chối trả hàng',
                        outlined: true,
                        onPressed: () => act(
                          context,
                          ref,
                          request,
                          'REJECTED',
                          'Từ chối trả hàng',
                        ),
                      ),
                    ],
                    if (canStaff(
                          ref.watch(staffRoleProvider),
                          'returns.receive',
                        ) &&
                        request.status == 'APPROVED')
                      AppButton(
                        'Nhận hàng khách trả',
                        onPressed: () => act(
                          context,
                          ref,
                          request,
                          'RECEIVED',
                          'Nhận hàng khách trả',
                        ),
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
