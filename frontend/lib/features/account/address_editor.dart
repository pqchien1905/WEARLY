part of 'address_page.dart';

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
  // Optional delivery pin from the map.
  late double? latitude = widget.address?.latitude;
  late double? longitude = widget.address?.longitude;
  bool busy = false;
  bool uncertain = false;
  bool reconcile = false, confirmingDiscard = false;
  final creationKey = newAddressCreationKey();
  late final Object identity;
  String? error;
  @override
  void initState() {
    super.initState();
    identity = _addressIdentity(ref);
    for (final c in [label, recipient, phone, address]) {
      c.addListener(changed);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  bool get dirty =>
      label.text.trim() != (widget.address?.label ?? '').trim() ||
      recipient.text.trim() != (widget.address?.recipient ?? '').trim() ||
      phone.text.trim() != (widget.address?.phone ?? '').trim() ||
      address.text.trim() != (widget.address?.address ?? '').trim() ||
      latitude != widget.address?.latitude ||
      longitude != widget.address?.longitude;

  void close() {
    if (busy) return;
    if (dirty && !uncertain && !reconcile) {
      setState(() => confirmingDiscard = true);
    } else {
      Navigator.pop(context);
    }
  }

  Widget field(
    String title,
    TextEditingController controller,
    int limit, {
    String? hint,
    int lines = 1,
    TextInputType? keyboard,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    readOnly: busy || uncertain || reconcile,
    maxLength: limit,
    maxLines: lines,
    keyboardType: keyboard,
    textInputAction: lines > 1 ? TextInputAction.newline : TextInputAction.next,
    decoration: InputDecoration(
      labelText: title,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      counterText: lines > 1 ? null : '',
    ),
    validator: (v) => (v ?? '').trim().runes.length > limit
        ? 'Tối đa $limit ký tự.'
        : validator(v),
  );

  @override
  void dispose() {
    for (final c in [label, recipient, phone, address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || reconcile) return;
    if (_addressIdentity(ref) != identity) {
      setState(
        () => error =
            'Phiên tài khoản đã thay đổi. Hãy đóng và mở lại sổ địa chỉ.',
      );
      return;
    }
    if (!(form.currentState?.validate() ?? false)) return;
    if (widget.address != null && !dirty) return;
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
              latitude: latitude,
              longitude: longitude,
            ),
            creationKey: creationKey,
          );
      if (mounted && _addressIdentity(ref) == identity) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted && _addressIdentity(ref) == identity) {
        setState(() {
          error = accountError(e);
          reconcile =
              (widget.address != null ||
                  (e is ApiException &&
                      [403, 404, 409, 410].contains(e.status))) &&
              ref.read(remoteApiProvider) &&
              (e is! ApiException || e.status != 400);
          uncertain =
              !reconcile &&
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
  Widget build(BuildContext context) {
    ref.watch(accountProvider);
    if (_addressIdentity(ref) != identity) return _endedAddressSession(context);
    if (confirmingDiscard) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => confirmingDiscard = false);
        },
        child: AlertDialog(
          title: const Text('Bỏ thay đổi chưa lưu?'),
          content: const Text(
            'Thông tin địa chỉ bạn vừa nhập sẽ không được lưu.',
          ),
          actions: [
            TextButton(
              onPressed: () => setState(() => confirmingDiscard = false),
              child: const Text('Tiếp tục nhập'),
            ),
            AppButton(
              'Bỏ thay đổi',
              outlined: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
    return PopScope(
      canPop: !busy && (!dirty || uncertain || reconcile),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          close();
        } else if (error != null &&
            (uncertain || reconcile) &&
            _addressIdentity(ref) == identity) {
          ref.invalidate(accountDetailsProvider);
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 20 : 24,
            ),
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          headingLevel: 2,
                          child: Text(
                            widget.address == null
                                ? 'Địa chỉ mới'
                                : 'Chỉnh sửa địa chỉ',
                            style: AccountTokens.heading.copyWith(fontSize: 20),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng địa chỉ',
                        onPressed: busy ? null : close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Điền thông tin để nhận hàng thuận tiện hơn.',
                    style: T.small,
                  ),
                  const SizedBox(height: 24),
                  field(
                    'Tên gợi nhớ',
                    label,
                    50,
                    hint: 'Nhà, Văn phòng…',
                    validator: requiredValue,
                  ),
                  const SizedBox(height: 16),
                  AccountGrid(
                    minColumnWidth: 230,
                    children: [
                      field(
                        'Người nhận',
                        recipient,
                        100,
                        validator: requiredValue,
                      ),
                      field(
                        'Điện thoại nhận hàng',
                        phone,
                        10,
                        keyboard: TextInputType.phone,
                        validator: (v) =>
                            RegExp(r'^0\d{9}$').hasMatch(v?.trim() ?? '')
                            ? null
                            : 'Nhập số điện thoại 10 chữ số.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  field(
                    'Địa chỉ nhận hàng',
                    address,
                    500,
                    hint: 'Gõ để tìm: số nhà, đường, phường/xã, tỉnh/thành',
                    lines: 3,
                    validator: (v) => (v?.trim().length ?? 0) >= 8
                        ? null
                        : 'Nhập địa chỉ đầy đủ, ít nhất 8 ký tự.',
                  ),
                  if (ref.watch(remoteApiProvider))
                    AddressFinder(
                      address: address,
                      latitude: latitude,
                      longitude: longitude,
                      enabled: !(busy || uncertain || reconcile),
                      onPin: (lat, lng) => setState(() {
                        latitude = lat;
                        longitude = lng;
                      }),
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
                  const Divider(height: 40),
                  if (uncertain)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Chưa xác nhận được kết quả. Thử lại cùng yêu cầu để tránh tạo trùng; hoặc đóng để kiểm tra sổ địa chỉ.',
                      ),
                    ),
                  if (reconcile)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Chưa xác nhận được kết quả. Kiểm tra lại sổ địa chỉ trước khi sửa tiếp.',
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          onPressed: busy ? null : close,
                          child: const Text('Hủy'),
                        ),
                        if (reconcile)
                          AppButton('Kiểm tra lại', onPressed: close)
                        else
                          Semantics(
                            button: busy ? true : null,
                            enabled: busy ? false : null,
                            label: busy ? 'Đang lưu địa chỉ…' : null,
                            excludeSemantics: busy,
                            child: AppButton(
                              uncertain
                                  ? 'Thử lại yêu cầu này'
                                  : ref.watch(remoteApiProvider)
                                  ? 'Lưu địa chỉ'
                                  : 'Lưu địa chỉ demo',
                              busy: busy,
                              onPressed: widget.address != null && !dirty
                                  ? null
                                  : save,
                              icon: Icons.check,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
