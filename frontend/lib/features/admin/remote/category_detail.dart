import 'taxonomy_detail.dart';
import 'taxonomy_kind.dart';

class RemoteCategoryDetail extends TaxonomyDetail {
  const RemoteCategoryDetail({super.key, required super.id, super.returnTo})
    : super(kind: TaxonomyKind.categories);
}
