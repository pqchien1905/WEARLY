import 'package:flutter/material.dart';
import '../../app/commerce_state.dart';
import '../../core/widgets/primitives.dart';

class CommerceFeedback extends StatelessWidget {
  const CommerceFeedback(this.store, {super.key, this.onRetry});
  final CommerceController store;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    if (store.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Đang tải dữ liệu'),
        ),
      );
    }
    if (store.error != null) {
      return StatePanel(
        title: 'Chưa tải được dữ liệu',
        message: '${store.error}',
        action: AppButton('Thử tải lại', onPressed: onRetry ?? store.refresh),
      );
    }
    return const SizedBox.shrink();
  }
}
