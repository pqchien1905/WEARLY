import 'taxonomy_workspace.dart';
import 'taxonomy_detail.dart';
import 'taxonomy_kind.dart';

class RemoteAdminBrands extends TaxonomyWorkspace {
  const RemoteAdminBrands({super.key}) : super(kind: TaxonomyKind.brands);
}

class RemoteBrandDetail extends TaxonomyDetail {
  const RemoteBrandDetail({super.key, required super.id, super.returnTo})
    : super(kind: TaxonomyKind.brands);
}
