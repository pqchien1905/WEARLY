part of 'orders_page.dart';

String orderPaymentLabel(Order order) => switch (order.paymentStatus) {
  'PAID' => order.total == 0 ? 'Không cần thanh toán' : 'Đã thanh toán',
  'PARTIALLY_REFUNDED' => 'Đã hoàn một phần',
  'REFUNDED' => 'Đã hoàn tiền',
  'FAILED' => 'Thanh toán thất bại',
  'CANCELLED' => 'Thanh toán đã hủy',
  _ => order.paymentProvider == 'cod' ? 'Chưa thu tiền' : 'Chờ thanh toán',
};

String orderSearchText(String value) {
  var text = value.toLowerCase();
  const replacements = {
    'àáạảãâầấậẩẫăằắặẳẵ': 'a',
    'èéẹẻẽêềếệểễ': 'e',
    'ìíịỉĩ': 'i',
    'òóọỏõôồốộổỗơờớợởỡ': 'o',
    'ùúụủũưừứựửữ': 'u',
    'ỳýỵỷỹ': 'y',
    'đ': 'd',
  };
  for (final entry in replacements.entries) {
    for (final character in entry.key.characters) {
      text = text.replaceAll(character, entry.value);
    }
  }
  return text.replaceAll(RegExp(r'[\u0300-\u036f]'), '').trim();
}

bool orderMatches(Order order, String query) {
  final text = orderSearchText(
    '${order.displayCode} ${order.id} '
    '${order.items.map((i) => '${i.name} ${i.sku}').join(' ')}',
  );
  return orderSearchText(query).split(RegExp(r'\s+')).every(text.contains);
}

class _OrderFilters extends StatelessWidget {
  const _OrderFilters({
    required this.search,
    required this.status,
    required this.orders,
    required this.remote,
    required this.onChanged,
    required this.onStatus,
    required this.partial,
  });
  final TextEditingController search;
  final String status;
  final List<Order> orders;
  final bool remote, partial;
  final VoidCallback onChanged;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) => AccountCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: search,
          onChanged: (_) => onChanged(),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: InputDecoration(
            labelText: 'Tìm mã đơn hoặc tên sản phẩm',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: 'Ví dụ: WR00001F hoặc áo cotton',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa từ khóa',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      search.clear();
                      onChanged();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in [
              '',
              ...orderStages.where((s) => !remote || s != 'Đang đóng gói'),
              'Đã hủy',
              if (remote) 'Đã hoàn về kho',
            ])
              ChoiceChip(
                label: Text(
                  '${value.isEmpty ? 'Tất cả' : value} (${value.isEmpty ? orders.length : orders.where((o) => o.status == value).length})',
                ),
                selected: status == value,
                onSelected: (_) => onStatus(value),
                showCheckmark: true,
              ),
          ],
        ),
        if (partial) ...[
          const SizedBox(height: 16),
          const Text(
            'Tìm kiếm, bộ lọc và số lượng trạng thái áp dụng cho các đơn đã tải. Chọn “Tải thêm đơn hàng” để xem các đơn cũ hơn.',
            style: T.small,
          ),
        ],
      ],
    ),
  );
}

class _OrderLoadNotice extends StatelessWidget {
  const _OrderLoadNotice({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: T.danger, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(message, style: T.body.copyWith(color: T.danger)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử tải lại'),
          ),
        ],
      ),
    ),
  );
}
