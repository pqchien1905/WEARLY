import 'package:flutter_riverpod/flutter_riverpod.dart';

// Route-level guard also covers sidebar links and browser Back navigation.
class ContentNavigation {
  Future<bool> Function()? check;
}

final contentNavigationProvider = Provider((ref) => ContentNavigation());
