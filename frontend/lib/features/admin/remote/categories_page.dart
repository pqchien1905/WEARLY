import 'taxonomy_workspace.dart';
import 'taxonomy_kind.dart';
export 'category_detail.dart';

class RemoteAdminCategories extends TaxonomyWorkspace {
  const RemoteAdminCategories({super.key})
    : super(kind: TaxonomyKind.categories);
}
