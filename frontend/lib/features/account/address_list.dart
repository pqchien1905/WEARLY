part of 'address_page.dart';

class _AddressList extends StatelessWidget {
  const _AddressList({
    required this.data,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onDefault,
  });
  final AccountDetails data;
  final bool busy;
  final ValueChanged<DeliveryAddress> onEdit, onDelete, onDefault;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = constraints.maxWidth >= 1000 * scale;
      final addresses = [
        ...data.addresses.where((a) => a.id == data.defaultAddressId),
        ...data.addresses.where((a) => a.id != data.defaultAddressId),
      ];
      Widget row(DeliveryAddress address) => _AddressRow(
        address: address,
        isDefault: address.id == data.defaultAddressId,
        wide: wide,
        onEdit: busy ? null : () => onEdit(address),
        onDelete: busy ? null : () => onDelete(address),
        onDefault: busy ? null : () => onDefault(address),
      );
      if (!wide) {
        return Column(
          children: [
            for (var i = 0; i < addresses.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              AccountCard(
                key: ValueKey('account-address-${addresses[i].id}'),
                child: row(addresses[i]),
              ),
            ],
          ],
        );
      }
      return Container(
        key: const ValueKey('addresses-table'),
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: T.surface,
          border: Border.all(color: T.line),
          borderRadius: T.radius,
        ),
        child: Column(
          children: [
            ColoredBox(
              color: T.canvas,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: _AddressColumns(
                  children: [
                    for (final title in [
                      'Tên gợi nhớ',
                      'Người nhận',
                      'Địa chỉ nhận hàng',
                      'Thao tác',
                    ])
                      Text(
                        title,
                        style: T.small.copyWith(fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
            for (final address in addresses) ...[
              const Divider(height: 1),
              Padding(
                key: ValueKey('account-address-${address.id}'),
                padding: const EdgeInsets.all(24),
                child: row(address),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _AddressColumns extends StatelessWidget {
  const _AddressColumns({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: children[0]),
        const SizedBox(width: 24),
        Expanded(flex: 3, child: children[1]),
        const SizedBox(width: 24),
        Expanded(flex: 5, child: children[2]),
        const SizedBox(width: 24),
        SizedBox(width: 240 * scale, child: children[3]),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.isDefault,
    required this.wide,
    required this.onEdit,
    required this.onDelete,
    required this.onDefault,
  });
  final DeliveryAddress address;
  final bool isDefault, wide;
  final VoidCallback? onEdit, onDelete, onDefault;

  @override
  Widget build(BuildContext context) {
    final label = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: T.soft,
            borderRadius: T.radius,
          ),
          child: const Icon(
            Icons.location_on_outlined,
            color: T.accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                address.label.isEmpty ? 'Địa chỉ nhận hàng' : address.label,
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              if (isDefault) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: T.soft,
                    borderRadius: T.radius,
                  ),
                  child: Text(
                    'Mặc định',
                    style: T.small.copyWith(
                      color: T.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final recipient = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wide) ...[
          const Text('Người nhận', style: T.small),
          const SizedBox(height: 6),
        ],
        Text(
          address.recipient,
          style: T.body.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(address.phone, style: T.body.copyWith(color: T.muted)),
      ],
    );
    final location = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wide) ...[
          const Text('Địa chỉ nhận hàng', style: T.small),
          const SizedBox(height: 6),
        ],
        Text(address.address, style: T.body),
      ],
    );
    final buttons = [
      OutlinedButton.icon(
        onPressed: onEdit,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          textStyle: T.small.copyWith(fontWeight: FontWeight.w500),
        ),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: Text('Chỉnh sửa', semanticsLabel: 'Sửa ${address.label}'),
      ),
      TextButton.icon(
        onPressed: onDelete,
        style: TextButton.styleFrom(
          foregroundColor: T.danger,
          textStyle: T.small.copyWith(fontWeight: FontWeight.w500),
        ),
        icon: const Icon(Icons.delete_outline, size: 16),
        label: Text('Xóa', semanticsLabel: 'Xóa ${address.label}'),
      ),
      if (!isDefault)
        TextButton.icon(
          onPressed: onDefault,
          style: TextButton.styleFrom(
            foregroundColor: T.accent,
            textStyle: T.small.copyWith(fontWeight: FontWeight.w500),
          ),
          icon: const Icon(Icons.check_circle_outline, size: 16),
          label: const Text('Đặt làm mặc định'),
        ),
    ];
    final actions = wide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: buttons[0]),
                  const SizedBox(width: 8),
                  buttons[1],
                ],
              ),
              if (!isDefault) ...[const SizedBox(height: 4), buttons[2]],
            ],
          )
        : Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: buttons,
          );
    if (wide) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 104),
        child: _AddressColumns(children: [label, recipient, location, actions]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const Divider(height: 32),
        AccountGrid(minColumnWidth: 240, children: [recipient, location]),
        const SizedBox(height: 20),
        actions,
      ],
    );
  }
}
