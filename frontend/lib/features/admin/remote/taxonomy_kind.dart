import 'package:flutter/material.dart';

enum TaxonomyKind {
  categories('danh mục', 'Danh mục', 'category'),
  brands('thương hiệu', 'Thương hiệu', 'brand');

  const TaxonomyKind(this.label, this.title, this.filter);
  final String label, title, filter;
  String get path => '/admin/$name';
  String get filterId => '${filter}Id';
  IconData get icon =>
      this == categories ? Icons.category_outlined : Icons.sell_outlined;
  String back(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
            !uri.hasScheme &&
            !uri.hasAuthority &&
            !uri.hasFragment &&
            uri.path == path
        ? uri.toString()
        : path;
  }

  String products(String id, {String? visibility}) => Uri(
    path: '/admin/products',
    queryParameters: {filterId: id, 'visibility': ?visibility},
  ).toString();
}
