import 'catalog.dart';

class StylistRequest {
  const StylistRequest({
    required this.prompt,
    this.budget = 1500000,
    this.size = 'M',
    this.style = '',
    this.color = '',
  });
  final String prompt, size, style, color;
  final int budget;
}

class StylistReply {
  const StylistReply(this.message, this.products);
  final String message;
  final List<Product> products;
  int get total => products.fold(0, (sum, p) => sum + p.price);
}

enum TryOnStatus { queued, processing, succeeded, failed, cancelled }

class TryOnJob {
  const TryOnJob(this.id, this.status, {this.error});
  final String id;
  final TryOnStatus status;
  final String? error;
}

abstract interface class StylistRepository {
  Future<StylistReply> reply(
    StylistRequest request, {
    String scenario = 'success',
  });
}

abstract interface class TryOnRepository {
  Stream<TryOnJob> create({
    required bool consent,
    required String sku,
    String scenario = 'success',
  });
  void cancel();
}
