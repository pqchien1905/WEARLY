import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../design/tokens.dart';

class CategoryChoices extends ConsumerWidget {
  const CategoryChoices({
    super.key,
    required this.onSelected,
    this.selected,
    this.home = false,
  });
  final ValueChanged<String> onSelected;
  final String? selected;
  final bool home;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(catalogCategoriesProvider)
      .when(
        data: (categories) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in categories.entries.where(
              (e) => !home || e.key.isNotEmpty,
            ))
              if (home)
                OutlinedButton(
                  onPressed: () => onSelected(entry.key),
                  child: Text(entry.value),
                )
              else
                ChoiceChip(
                  label: Text(entry.value),
                  selected: entry.key == selected,
                  onSelected: (_) => onSelected(entry.key),
                ),
          ],
        ),
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            const Text('Chưa tải được danh mục.', style: T.small),
            TextButton(
              onPressed: () => ref.invalidate(catalogCategoriesProvider),
              child: const Text('Tải lại danh mục'),
            ),
          ],
        ),
      );
}
