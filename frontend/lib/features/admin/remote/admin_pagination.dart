import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_admin.dart';
import 'admin_presentation.dart';

/// Uses the server's page and limit so the footer always describes the rows shown.
class AdminPagination extends StatelessWidget {
  const AdminPagination({
    super.key,
    required this.page,
    required this.onPage,
    this.onPageSize,
    this.loading = false,
  });
  final AdminPage page;
  final ValueChanged<int> onPage;
  final ValueChanged<int>? onPageSize;
  final bool loading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final pages = (page.total / page.limit).ceil().clamp(1, 10000);
      final current = page.page.clamp(1, pages);
      final start = page.items.isEmpty ? 0 : (current - 1) * page.limit + 1;
      final end = page.items.isEmpty
          ? 0
          : ((current - 1) * page.limit + page.items.length).clamp(
              0,
              page.total,
            );
      final wide =
          c.maxWidth >= 900 && MediaQuery.textScalerOf(context).scale(14) <= 18;
      final info = Semantics(
        liveRegion: true,
        child: Text(
          'Trang $current/$pages · ${adminNumber(start)}–${adminNumber(end)} / ${adminNumber(page.total)} mục',
          style: T.small,
        ),
      );
      final size = onPageSize == null
          ? Text('${page.limit} mục / trang', style: T.small)
          : SizedBox(
              width: 150,
              child: DropdownButtonFormField<int>(
                key: ValueKey('page-size-${page.limit}'),
                initialValue: page.limit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mỗi trang',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: ({10, 20, 50, 100, page.limit}.toList()..sort())
                    .map(
                      (n) => DropdownMenuItem(value: n, child: Text('$n mục')),
                    )
                    .toList(),
                onChanged: loading
                    ? null
                    : (n) {
                        if (n != null && n != page.limit) onPageSize!(n);
                      },
              ),
            );
      final numbers = <int>{
        1,
        pages,
        for (var n = current - 1; n <= current + 1; n++)
          if (n >= 1 && n <= pages) n,
      }.toList()..sort();
      Widget move(String label, int target, bool enabled) => AppButton(
        label,
        outlined: true,
        onPressed: loading || !enabled
            ? null
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                onPage(target);
              },
      );
      final navigation = Wrap(
        spacing: 4,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          move('Trang trước', current - 1, current > 1),
          if (wide)
            for (var i = 0; i < numbers.length; i++) ...[
              if (i > 0 && numbers[i] > numbers[i - 1] + 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('…', style: T.small),
                ),
              Semantics(
                selected: current == numbers[i],
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    backgroundColor: current == numbers[i] ? T.soft : null,
                  ),
                  onPressed: loading || current == numbers[i]
                      ? null
                      : () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          onPage(numbers[i]);
                        },
                  child: Text(
                    '${numbers[i]}',
                    style: TextStyle(
                      color: current == numbers[i] ? T.accent : T.ink,
                    ),
                  ),
                ),
              ),
            ],
          move('Trang sau', current + 1, current < pages),
        ],
      );
      return Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: T.line)),
        ),
        child: wide
            ? Row(
                children: [
                  Expanded(child: info),
                  size,
                  const SizedBox(width: 20),
                  navigation,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [info, size],
                  ),
                  const SizedBox(height: 12),
                  navigation,
                ],
              ),
      );
    },
  );
}
