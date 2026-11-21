import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'promotion_list_widgets.dart';
import 'promotion_editor.dart';
import 'promotion_actions.dart';
import 'promotion_widgets.dart';

class RemotePromotionsPage extends ConsumerStatefulWidget {
  const RemotePromotionsPage({super.key});
  @override
  ConsumerState<RemotePromotionsPage> createState() => _PromotionsState();
}

class _PromotionsState extends ConsumerState<RemotePromotionsPage> {
  final search = TextEditingController();
  final form = GlobalKey<FormState>();
  String? applied;
  Map<String, String> localParams = {};
  Map<String, String> get params => GoRouter.maybeOf(context) == null
      ? localParams
      : GoRouterState.of(context).uri.queryParameters;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (applied != (params['q'] ?? '')) {
      applied = params['q'] ?? '';
      search.text = applied!;
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void apply(
    Map<String, String?> changes, {
    bool clear = false,
    bool keepPage = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = <String, String>{if (!clear) ...params};
    if (!keepPage) next.remove('page');
    for (final e in changes.entries) {
      if (e.value == null || e.value!.isEmpty) {
        next.remove(e.key);
      } else {
        next[e.key] = e.value!;
      }
    }
    if (clear) {
      form.currentState?.reset();
      search.clear();
    }
    if (GoRouter.maybeOf(context) == null) {
      setState(() => localParams = next);
      return;
    }
    context.go(
      Uri(
        path: '/admin/promotions',
        queryParameters: next.isEmpty ? null : next,
      ).toString(),
    );
  }

  void submit() {
    if (form.currentState!.validate()) apply({'q': search.text.trim()});
  }

  Widget select(
    String label,
    String key,
    Map<String, String> choices, {
    String fallback = '',
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$key-${params[key]}'),
    initialValue: choices.containsKey(params[key] ?? fallback)
        ? params[key] ?? fallback
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: choices.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) => apply({key: v}),
  );
  void open(AdminRecord row) => context.go(
    Uri(
      path: '/admin/promotions/${row['id']}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  @override
  Widget build(BuildContext context) {
    final key = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    final data = ref.watch(adminPromotionsProvider(key));
    final summary = ref.watch(adminPromotionSummaryProvider);
    final loaded = data.asData?.value;
    if (loaded != null &&
        !data.isLoading &&
        (int.tryParse(params['page'] ?? '1') ?? 1) != loaded.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            Uri(
                  queryParameters: {'page': '1', 'limit': '10', ...params},
                ).query ==
                key) {
          context.replace(
            Uri(
              path: '/admin/promotions',
              queryParameters: {...params, 'page': '${loaded.page}'},
            ).toString(),
          );
        }
      });
    }
    void reload() => refreshAdmin(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Quản lý khuyến mãi',
          'Giảm giá tự động theo sản phẩm và mã ưu đãi cho đơn hàng.',
          actions: [
            AppButton(
              'Thêm khuyến mãi',
              icon: Icons.add,
              onPressed: () => editPromotion(context, ref, null),
            ),
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              onPressed: data.isLoading || summary.isLoading ? null : reload,
            ),
          ],
        ),
        AdminAsync(
          value: summary,
          reload: reload,
          builder: (s) => PromotionSummary(
            summary: s,
            status: params['status'] ?? '',
            onSelect: (status) => apply({'status': status}, clear: true),
          ),
        ),
        AdminCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final field = TextFormField(
                      controller: search,
                      decoration: const InputDecoration(
                        labelText: 'Tìm kiếm khuyến mãi',
                        hintText: 'Tên chương trình hoặc mã ưu đãi',
                        prefixIcon: Icon(Icons.search),
                      ),
                      validator: (v) =>
                          (v ?? '').length > 100 ? 'Tối đa 100 ký tự.' : null,
                      onFieldSubmitted: (_) => submit(),
                    );
                    final button = AppButton(
                      'Tìm kiếm',
                      outlined: true,
                      onPressed: submit,
                    );
                    return c.maxWidth < 450 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              field,
                              const SizedBox(height: 12),
                              button,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 680,
                                  ),
                                  child: field,
                                ),
                              ),
                              const SizedBox(width: 12),
                              button,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) {
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 18;
                    final columns = c.maxWidth >= 1400 && !largeText
                        ? 5
                        : c.maxWidth >= 900 && !largeText
                        ? 3
                        : c.maxWidth >= 580 && !largeText
                        ? 2
                        : 1;
                    final width = columns == 1
                        ? c.maxWidth
                        : ((c.maxWidth - (columns - 1) * 12) / columns).clamp(
                            0.0,
                            300.0,
                          );
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: width,
                          child: select('Trạng thái', 'status', {
                            '': 'Tất cả trạng thái',
                            ...promotionStatuses,
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Loại giảm giá', 'kind', {
                            '': 'Tất cả loại',
                            'FIXED': 'Số tiền VND',
                            'PERCENT': 'Phần trăm',
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Sắp xếp', 'sort', {
                            'newest': 'Mới tạo',
                            'updated': 'Mới cập nhật',
                            'code_asc': 'Mã A–Z',
                            'expiry': 'Hết hạn sớm nhất',
                            'usage_desc': 'Nhiều lượt dùng nhất',
                          }, fallback: 'newest'),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Cách áp dụng', 'application', {
                            '': 'Tất cả cách áp dụng',
                            'AUTOMATIC': 'Tự động giảm giá',
                            'CODE': 'Khách nhập mã',
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Phạm vi', 'scope', {
                            '': 'Tất cả phạm vi',
                            'ALL': 'Toàn bộ sản phẩm',
                            'PRODUCTS': 'Một số sản phẩm',
                          }),
                        ),
                        TextButton.icon(
                          onPressed: () => apply({}, clear: true),
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 18,
                          ),
                          label: const Text('Xóa bộ lọc'),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 32),
                AdminAsync(
                  value: data,
                  reload: reload,
                  builder: (result) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${adminNumber(result.total)} khuyến mãi phù hợp bộ lọc',
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (result.items.isEmpty)
                        StatePanel(
                          title: 'Chưa có mã khuyến mãi phù hợp',
                          message:
                              'Thử đổi từ khóa, xóa bộ lọc hoặc thêm mã khuyến mãi mới.',
                          action: AppButton(
                            'Xóa bộ lọc',
                            outlined: true,
                            onPressed: () => apply({}, clear: true),
                          ),
                        ),
                      if (result.items.isNotEmpty) const PromotionListHeader(),
                      for (final row in result.items)
                        PromotionListItem(
                          row: row,
                          onOpen: () => open(row),
                          onEdit: () => editPromotion(context, ref, row),
                          onAction: (action) {
                            switch (action) {
                              case PromotionListAction.toggle:
                                changePromotion(context, ref, row);
                              case PromotionListAction.delete:
                                if (row['canDelete'] == true) {
                                  changePromotion(
                                    context,
                                    ref,
                                    row,
                                    remove: true,
                                  );
                                }
                            }
                          },
                        ),
                      const SizedBox(height: 20),
                      AdminPagination(
                        page: result,
                        loading: data.isLoading,
                        onPage: (n) => apply({'page': '$n'}, keepPage: true),
                        onPageSize: (n) => apply({'limit': '$n'}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
