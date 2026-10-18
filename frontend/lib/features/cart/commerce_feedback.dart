import 'package:flutter/material.dart';
import '../../app/commerce_state.dart';
import '../../core/widgets/primitives.dart';

class CommerceFeedback extends StatelessWidget {
  const CommerceFeedback(this.state, {super.key, required this.onRetry});
  final CommerceLoadState state;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Đang tải dữ liệu'),
        ),
      );
    }
    if (state.error != null) {
      return StatePanel(
        title: 'Chưa tải được dữ liệu',
        message: '${state.error}',
        action: AppButton('Thử tải lại', onPressed: onRetry),
      );
    }
    return const SizedBox.shrink();
  }
}
