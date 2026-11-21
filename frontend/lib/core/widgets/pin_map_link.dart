import 'package:flutter/material.dart';
import '../platform/device_location.dart';

/// "Xem vị trí ghim" link that opens the delivery pin on OpenStreetMap.
class PinMapLink extends StatelessWidget {
  const PinMapLink({
    super.key,
    required this.latitude,
    required this.longitude,
    this.label = 'Xem vị trí ghim trên bản đồ',
  });
  final double latitude, longitude;
  final String label;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      onPressed: () => openMapLink(pinMapLink(latitude, longitude)),
      icon: const Icon(Icons.map_outlined, size: 18),
      label: Text(label),
    ),
  );
}
