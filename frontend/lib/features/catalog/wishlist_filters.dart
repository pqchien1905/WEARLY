part of 'remote_wishlist_page.dart';

const _stockLabels = {
  'all': 'Tất cả',
  'available': 'Còn hàng',
  'sold_out': 'Hết hàng',
  'unavailable': 'Ngừng bán',
};
const _sortLabels = {
  'newest': 'Lưu gần đây',
  'price_asc': 'Giá thấp đến cao',
  'price_desc': 'Giá cao đến thấp',
};
String _stockOf(Product? p) => p == null
    ? 'unavailable'
    : p.variants.any((v) => v.stock > 0)
    ? 'available'
    : 'sold_out';
String _searchText(String value) {
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

class _WishlistFilters extends StatelessWidget {
  const _WishlistFilters({
    required this.search,
    required this.stock,
    required this.sort,
    required this.records,
    required this.onSearch,
    required this.onStock,
    required this.onSort,
    required this.onClear,
  });
  final TextEditingController search;
  final String stock, sort;
  final List<MapEntry<String, Product?>> records;
  final ValueChanged<String> onSearch, onStock, onSort;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => AccountCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (_, c) {
            final searchField = TextField(
              controller: search,
              maxLength: 100,
              textInputAction: TextInputAction.search,
              onChanged: onSearch,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                labelText: 'Tìm sản phẩm đã lưu',
                hintText: 'Tên sản phẩm, chất liệu, màu sắc',
                counterText: '',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa từ khóa',
                        onPressed: () => onSearch(''),
                        icon: const Icon(Icons.close),
                      ),
              ),
            );
            final sortField = DropdownButtonFormField<String>(
              key: ValueKey(sort),
              initialValue: sort,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sắp xếp',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              items: [
                for (final entry in _sortLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) onSort(value);
              },
            );
            if (c.maxWidth < 650 * MediaQuery.textScalerOf(context).scale(1)) {
              return Column(
                children: [searchField, const SizedBox(height: 16), sortField],
              );
            }
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 16),
                SizedBox(width: 220, child: sortField),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final entry in _stockLabels.entries)
              ChoiceChip(
                label: Text(
                  '${entry.value} (${entry.key == 'all' ? records.length : records.where((r) => _stockOf(r.value) == entry.key).length})',
                ),
                selected: stock == entry.key,
                onSelected: (_) => onStock(entry.key),
              ),
            if (stock != 'all' || sort != 'newest' || search.text.isNotEmpty)
              TextButton(onPressed: onClear, child: const Text('Đặt lại')),
          ],
        ),
      ],
    ),
  );
}
