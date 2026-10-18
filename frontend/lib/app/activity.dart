import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActivityEntry {
  const ActivityEntry(this.feature, this.status, this.at);
  final String feature, status;
  final DateTime at;
}

final activityProvider =
    NotifierProvider<ActivityController, List<ActivityEntry>>(
      ActivityController.new,
    );

class ActivityController extends Notifier<List<ActivityEntry>> {
  @override
  List<ActivityEntry> build() => [];
  void add(String feature, String status) => state = [
    ActivityEntry(feature, status, DateTime.now()),
    ...state,
  ].take(100).toList();
}
