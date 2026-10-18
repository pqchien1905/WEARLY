import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/foundation.dart';
import '../../app/providers.dart';
import '../../domain/catalog.dart';

class Promotion {
  const Promotion(this.code, this.discount, this.enabled);
  final String code;
  final int discount;
  final bool enabled;
}

final adminStateProvider = ChangeNotifierProvider<AdminState>(
  (ref) => AdminState(),
);

class AdminState extends ChangeNotifier {
  final List<Promotion> promotions = [const Promotion('WEARLYDEMO', 10, false)];
  final List<String> audit = [];
  String banner = 'Mặc theo cách bạn.',
      policy = 'Đổi size trong 7 ngày (chính sách demo).';
  void log(String action) {
    audit.insert(0, action);
    notifyListeners();
  }

  void promotion(Promotion value) {
    final i = promotions.indexWhere((p) => p.code == value.code);
    if (i < 0) {
      promotions.add(value);
    } else {
      promotions[i] = value;
    }
    log('Cập nhật mã ${value.code}');
  }

  void deletePromotion(String code) {
    promotions.removeWhere((p) => p.code == code);
    log('Xóa mã $code');
  }

  void content(String nextBanner, String nextPolicy) {
    banner = nextBanner;
    policy = nextPolicy;
    log('Lưu nội dung demo');
  }
}

final adminProductsProvider = FutureProvider<ProductPage>((ref) {
  ref.watch(catalogRevisionProvider);
  return ref
      .watch(productRepositoryProvider)
      .list(const ProductQuery(limit: 100, includeInactive: true));
});
