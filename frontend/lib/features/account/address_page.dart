import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/account_details.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/remote_route_gate.dart';
import '../../core/network/api_client.dart';
import '../../core/design/account_tokens.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'account_navigation.dart';
import 'account_components.dart';

part 'address_list.dart';
part 'address_editor.dart';

class AddressPage extends ConsumerWidget {
  const AddressPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(accountProvider);
    final remote = ref.watch(remoteApiProvider);
    if (user == null) {
      return const AccountFrame(
        title: 'Sổ địa chỉ',
        current: '/account/addresses',
        child: LoginRequired(next: '/account/addresses'),
      );
    }
    return _AddressBook(
      key: ValueKey((
        user.id,
        user.email,
        remote ? ref.watch(sessionTokensProvider).generation : 0,
      )),
    );
  }
}

class _AddressBook extends ConsumerStatefulWidget {
  const _AddressBook({super.key});
  @override
  ConsumerState<_AddressBook> createState() => _AddressBookState();
}

class _AddressBookState extends ConsumerState<_AddressBook> {
  bool busy = false;
  AccountDetails? snapshot;
  String? notice, operationError;
  late final identity = _addressIdentity(ref);
  bool get sameSession => _addressIdentity(ref) == identity;
  bool get fresh =>
      !ref.read(accountDetailsProvider).isLoading &&
      !ref.read(accountDetailsProvider).hasError;

  Future<void> reload() async {
    ref.invalidate(accountDetailsProvider);
    try {
      await ref.read(accountDetailsProvider.future);
    } catch (_) {
      // The state below retains the last address book and offers a read retry.
    }
  }

  Future<void> edit([DeliveryAddress? address]) async {
    if (busy || !fresh || !sameSession) return;
    setState(() {
      busy = true;
      notice = null;
      operationError = null;
    });
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddressEditor(address: address),
    );
    if (!mounted || !sameSession) return;
    setState(() {
      busy = false;
      if (saved == true) {
        notice = ref.read(remoteApiProvider)
            ? 'Đã lưu địa chỉ.'
            : 'Đã lưu địa chỉ trong phiên demo.';
      }
    });
  }

  Future<void> perform(Future<void> Function() action, String success) async {
    if (busy || !fresh || !sameSession) return;
    setState(() {
      busy = true;
      notice = null;
      operationError = null;
    });
    try {
      await action();
      if (mounted && sameSession) setState(() => notice = success);
    } catch (e) {
      if (mounted && sameSession) {
        setState(() => operationError = accountError(e));
        await reload();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(DeliveryAddress address) async {
    if (busy || !fresh || !sameSession) return;
    setState(() => busy = true);
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAddressConfirmation(
        address: address,
        isDefault: snapshot?.defaultAddressId == address.id,
        hasOthers: (snapshot?.addresses.length ?? 0) > 1,
      ),
    );
    if (!mounted || !sameSession) return;
    setState(() => busy = false);
    if (yes != true) return;
    await perform(
      () => ref.read(accountDetailsProvider.notifier).deleteAddress(address.id),
      'Đã xóa địa chỉ.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    final result = ref.watch(accountDetailsProvider);
    if (result is AsyncData<AccountDetails> && !result.isLoading) {
      snapshot = result.value;
    }
    final data = snapshot;
    final locked = busy || result.isLoading || result.hasError;
    return AccountFrame(
      title: 'Sổ địa chỉ',
      current: '/account/addresses',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!remote)
            const AccountNotice(
              text:
                  'Lưu tối đa 5 địa chỉ trong phiên tài khoản demo. Bạn chủ động chọn địa chỉ khi checkout; không có giao hàng thật.',
            ),
          if (!remote) const SizedBox(height: 24),
          if (notice != null || operationError != null) ...[
            Semantics(
              liveRegion: true,
              child: AccountNotice(
                text: operationError ?? notice!,
                icon: operationError == null
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (data != null)
            AccountToolbar(
              label: '${data.addresses.length} địa chỉ đã lưu',
              actions: [
                TextButton.icon(
                  onPressed: locked
                      ? null
                      : () {
                          setState(() {
                            notice = null;
                            operationError = null;
                          });
                          reload();
                        },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(result.isLoading ? 'Đang tải lại…' : 'Tải lại'),
                ),
                AppButton(
                  'Thêm địa chỉ',
                  icon: Icons.add,
                  onPressed: locked || (!remote && data.addresses.length >= 5)
                      ? null
                      : () => edit(),
                ),
              ],
            ),
          if (!remote && data != null && data.addresses.length >= 5)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Đã đủ 5 địa chỉ. Sửa hoặc xóa một địa chỉ để thêm mới.',
                style: T.small,
              ),
            ),
          const SizedBox(height: 24),
          if (busy) ...[
            Semantics(
              liveRegion: true,
              child: const Text('Đang xử lý địa chỉ…', style: T.small),
            ),
            const SizedBox(height: 12),
          ],
          if (result.isLoading && data == null)
            const AccountLoading(label: 'Đang tải sổ địa chỉ…')
          else if (result.isLoading) ...[
            const LinearProgressIndicator(
              semanticsLabel: 'Đang tải lại sổ địa chỉ',
            ),
            const SizedBox(height: 16),
          ],
          if (result.hasError) ...[
            AccountCard(
              title: data == null
                  ? 'Chưa tải được sổ địa chỉ'
                  : 'Chưa cập nhật được sổ địa chỉ',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(accountError(result.error!), style: T.body),
                  ),
                  if (data != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Đang hiển thị địa chỉ đã tải. Tải lại trước khi tiếp tục thay đổi.',
                      style: T.small,
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppButton(
                    'Thử lại',
                    outlined: true,
                    onPressed: busy ? null : reload,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (data != null && data.addresses.isEmpty)
            const AccountEmptyState(
              title: 'Chưa có địa chỉ nhận hàng',
              message:
                  'Thêm địa chỉ nhà hoặc nơi làm việc để điền nhanh ở bước đặt hàng.',
              icon: Icons.location_on_outlined,
            ),
          if (data != null && data.addresses.isNotEmpty)
            _AddressList(
              data: data,
              busy: locked,
              onEdit: edit,
              onDelete: remove,
              onDefault: (address) => perform(
                () => ref
                    .read(accountDetailsProvider.notifier)
                    .setDefault(address.id),
                'Đã đổi địa chỉ mặc định.',
              ),
            ),
        ],
      ),
    );
  }
}

Object _addressIdentity(WidgetRef ref) => (
  ref.read(accountProvider)?.id,
  ref.read(accountProvider)?.email,
  ref.read(remoteApiProvider)
      ? ref.read(apiClientProvider).tokens.generation
      : 0,
);

class _DeleteAddressConfirmation extends ConsumerStatefulWidget {
  const _DeleteAddressConfirmation({
    required this.address,
    required this.isDefault,
    required this.hasOthers,
  });
  final DeliveryAddress address;
  final bool isDefault, hasOthers;
  @override
  ConsumerState<_DeleteAddressConfirmation> createState() =>
      _DeleteAddressConfirmationState();
}

class _DeleteAddressConfirmationState
    extends ConsumerState<_DeleteAddressConfirmation> {
  late final identity = _addressIdentity(ref);
  @override
  Widget build(BuildContext context) {
    ref.watch(accountProvider);
    if (_addressIdentity(ref) != identity) return _endedAddressSession(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('Xóa địa chỉ ${widget.address.label}?'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.address.recipient} · ${widget.address.phone}',
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(widget.address.address, style: T.body),
              const SizedBox(height: 16),
              const Text(
                'Thông tin của đơn đã tạo vẫn được giữ nguyên. Địa chỉ đã xóa không thể khôi phục.',
                style: T.body,
              ),
              if (widget.isDefault && widget.hasOthers) ...[
                const SizedBox(height: 12),
                const Text(
                  'Địa chỉ còn lại được lưu sớm nhất sẽ trở thành mặc định.',
                  style: T.small,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Giữ lại'),
        ),
        AppButton(
          'Xác nhận',
          onPressed: () {
            if (_addressIdentity(ref) == identity) Navigator.pop(context, true);
          },
        ),
      ],
    );
  }
}

Widget _endedAddressSession(BuildContext context) => AlertDialog(
  title: const Text('Phiên tài khoản đã thay đổi'),
  content: const Text('Mở lại sổ địa chỉ để tiếp tục với tài khoản hiện tại.'),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Đóng'),
    ),
  ],
);
