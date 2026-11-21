part of 'reviews_page.dart';

class _ReviewFilters extends StatelessWidget {
  const _ReviewFilters({
    required this.search,
    required this.rating,
    required this.onChanged,
    required this.onSubmitted,
    required this.onRating,
    required this.onClear,
  });
  final TextEditingController search;
  final int? rating;
  final VoidCallback onChanged, onSubmitted, onClear;
  final ValueChanged<int?> onRating;

  @override
  Widget build(BuildContext context) => AccountCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: search,
          maxLength: 100,
          textInputAction: TextInputAction.search,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) {
            onSubmitted();
            FocusScope.of(context).unfocus();
          },
          decoration: InputDecoration(
            labelText: 'Tìm đánh giá',
            hintText: 'Tên sản phẩm hoặc nội dung',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            counterText: '',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa từ khóa',
                    onPressed: () {
                      search.clear();
                      onChanged();
                      onSubmitted();
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Tất cả'),
              selected: rating == null,
              onSelected: (_) => onRating(null),
            ),
            for (var star = 5; star >= 1; star--)
              ChoiceChip(
                label: Text('$star sao'),
                selected: rating == star,
                onSelected: (_) => onRating(star),
              ),
            if (rating != null || search.text.isNotEmpty)
              TextButton(onPressed: onClear, child: const Text('Đặt lại')),
          ],
        ),
      ],
    ),
  );
}
