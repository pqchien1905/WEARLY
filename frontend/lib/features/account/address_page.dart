import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/account_details.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../core/network/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'account_navigation.dart';

class AddressPage extends ConsumerStatefulWidget {
  const AddressPage({super.key});
  @override
  ConsumerState<AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends ConsumerState<AddressPage> {
  bool busy = false;
  Future<void> edit([DeliveryAddress? address]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddressEditor(address: address),
    );
    if (mounted && saved != true && ref.read(remoteApiProvider)) {
      ref.invalidate(accountDetailsProvider);
    }
    if (mounted && saved == true) {
      toast(
        context,
        ref.read(remoteApiProvider)
            ? 'Đã lưu địa chỉ.'
            : 'Đã lưu địa chỉ trong phiên demo.',
      );
    }
  }

  Future<void> perform(Future<void> Function() action, String success) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) toast(context, success);
    } catch (e) {
      if (mounted) toast(context, accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AccountFrame(
    title: 'Những nơi nhận đồ.',
    current: '/account/addresses',
    child: AccountDataView(
      builder: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DemoNotice(
            text: ref.watch(remoteApiProvider)
                ? 'Địa chỉ được lưu trong tài khoản. Chọn địa chỉ nhận hàng khi đặt đơn.'
                : 'Lưu tối đa 5 địa chỉ trong phiên tài khoản demo. Bạn chủ động chọn địa chỉ khi checkout; không có giao hàng thật.',
          ),
          const SizedBox(height: 24),
          AppButton(
            'Thêm địa chỉ',
            icon: Icons.add,
            onPressed:
                busy ||
                    (!ref.watch(remoteApiProvider) &&
                        data.addresses.length >= 5)
                ? null
                : () => edit(),
          ),
          if (!ref.watch(remoteApiProvider) && data.addresses.length >= 5)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Đã đủ 5 địa chỉ. Sửa hoặc xóa một địa chỉ để thêm mới.',
                style: T.small,
              ),
            ),
          const SizedBox(height: 24),
          if (data.addresses.isEmpty)
            const StatePanel(
              title: 'Chưa có địa chỉ nhận hàng',
              message:
                  'Thêm địa chỉ nhà hoặc nơi làm việc để điền nhanh ở bước đặt hàng.',
              icon: Icons.location_on_outlined,
            ),
          LayoutBuilder(
            builder: (_, c) => Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                for (final a in data.addresses)
                  SizedBox(
                    width: c.maxWidth < 750
                        ? c.maxWidth
                        : (c.maxWidth - 24) / 2,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: T.radius,
                        border: Border.all(
                          color: a.id == data.defaultAddressId
                              ? T.accent
                              : T.line,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                a.label,
                                style: T.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (a.id == data.defaultAddressId)
                                Text(
                                  'Mặc định',
                                  style: T.small.copyWith(color: T.accent),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(a.recipient),
                          Text(a.phone, style: T.small),
                          const SizedBox(height: 8),
                          Text(a.address),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: busy ? null : () => edit(a),
                                child: Text('Sửa ${a.label}'),
                              ),
                              if (a.id != data.defaultAddressId)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => perform(
                                          () => ref
                                              .read(
                                                accountDetailsProvider.notifier,
                                              )
                                              .setDefault(a.id),
                                          'Đã đổi địa chỉ mặc định.',
                                        ),
                                  child: const Text('Đặt làm mặc định'),
                                ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final yes = await confirmAction(
                                          context,
                                          'Xóa địa chỉ ${a.label}?',
                                          ref.read(remoteApiProvider)
                                              ? 'Địa chỉ sẽ được xóa khỏi tài khoản. Thông tin của đơn đã tạo vẫn được giữ nguyên.'
                                              : 'Địa chỉ sẽ được xóa khỏi phiên. Thông tin của đơn đã tạo vẫn được giữ nguyên.',
                                        );
                                        if (!mounted || !yes) return;
                                        await perform(
                                          () => ref
                                              .read(
                                                accountDetailsProvider.notifier,
                                              )
                                              .deleteAddress(a.id),
                                          'Đã xóa địa chỉ.',
                                        );
                                      },
                                child: Text(
                                  'Xóa ${a.label}',
                                  style: const TextStyle(color: T.danger),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AddressEditor extends ConsumerStatefulWidget {
  const _AddressEditor({this.address});
  final DeliveryAddress? address;
  @override
  ConsumerState<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ConsumerState<_AddressEditor> {
  final form = GlobalKey<FormState>();
  late final label = TextEditingController(text: widget.address?.label);
  late final recipient = TextEditingController(text: widget.address?.recipient);
  late final phone = TextEditingController(text: widget.address?.phone);
  late final address = TextEditingController(text: widget.address?.address);
  bool busy = false;
  bool uncertain = false;
  final creationKey = newAddressCreationKey();
  late final String? identity;
  late final int sessionGeneration;
  String? error;
  @override
  void initState() {
    super.initState();
    identity = ref.read(accountProvider)?.email;
    sessionGeneration = ref.read(remoteApiProvider)
        ? ref.read(apiClientProvider).tokens.generation
        : 0;
  }

  @override
  void dispose() {
    for (final c in [label, recipient, phone, address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || busy) return;
    if (ref.read(accountProvider)?.email != identity ||
        (ref.read(remoteApiProvider) &&
            ref.read(apiClientProvider).tokens.generation !=
                sessionGeneration)) {
      setState(
        () => error =
            'Phiên tài khoản đã thay đổi. Hãy đóng và mở lại sổ địa chỉ.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(accountDetailsProvider.notifier)
          .saveAddress(
            DeliveryAddress(
              id: widget.address?.id ?? '',
              label: label.text,
              recipient: recipient.text,
              phone: phone.text,
              address: address.text,
            ),
            creationKey: creationKey,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = accountError(e);
          uncertain =
              widget.address == null &&
              ref.read(remoteApiProvider) &&
              (e is! ApiException || e.status != 400);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.address == null
                          ? 'Địa chỉ mới'
                          : 'Chỉnh sửa địa chỉ',
                      style: T.display(26),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng địa chỉ',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AppField(
                label: 'Tên gợi nhớ',
                hint: 'Nhà, Văn phòng…',
                controller: label,
                readOnly: busy || uncertain,
                validator: requiredValue,
              ),
              const SizedBox(height: 16),
              AppField(
                label: 'Người nhận',
                controller: recipient,
                readOnly: busy || uncertain,
                validator: requiredValue,
              ),
              const SizedBox(height: 16),
              AppField(
                label: 'Điện thoại nhận hàng',
                controller: phone,
                readOnly: busy || uncertain,
                keyboardType: TextInputType.phone,
                validator: (v) => RegExp(r'^0\d{9}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Nhập số điện thoại 10 chữ số.',
              ),
              const SizedBox(height: 16),
              AppField(
                label: 'Địa chỉ nhận hàng',
                controller: address,
                readOnly: busy || uncertain,
                maxLines: 3,
                validator: (v) => (v?.trim().length ?? 0) >= 8
                    ? null
                    : 'Nhập địa chỉ đầy đủ, ít nhất 8 ký tự.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: const TextStyle(color: T.danger),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              if (uncertain)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Chưa xác nhận được kết quả. Thử lại cùng yêu cầu để tránh tạo trùng; hoặc đóng để kiểm tra sổ địa chỉ.',
                  ),
                ),
              AppButton(
                uncertain
                    ? 'Thử lại yêu cầu này'
                    : ref.watch(remoteApiProvider)
                    ? 'Lưu địa chỉ'
                    : 'Lưu địa chỉ demo',
                busy: busy,
                onPressed: save,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
