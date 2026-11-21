import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../app/config.dart';
import '../../core/design/tokens.dart';
import '../../core/platform/device_location.dart';
import '../../data/remote_geo.dart';

/// Map + type-ahead for a delivery address.
///
/// * Typing in [address] shows matching places in Vietnam; picking one fills
///   the text and moves the pin there.
/// * The pin stays in the middle of the map: drag the map to put it on the
///   exact gate/building. The shop then proposes the address at that spot.
/// * The pin is optional and is what the courier navigates to.
class AddressFinder extends ConsumerStatefulWidget {
  const AddressFinder({
    super.key,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.onPin,
    this.enabled = true,
  });
  final TextEditingController address;
  final double? latitude, longitude;
  final void Function(double? latitude, double? longitude) onPin;
  final bool enabled;

  @override
  ConsumerState<AddressFinder> createState() => _AddressFinderState();
}

class _AddressFinderState extends ConsumerState<AddressFinder> {
  // Whole country until the shopper searches, pins or locates themself.
  static const _vietnam = LatLng(16.2, 106.4);
  static const _pinZoom = 15.0;
  final map = MapController();
  Timer? typing, settling;
  List<GeoPlace> suggestions = const [];
  GeoPlace? nearPin;
  bool searching = false, resolving = false, locating = false;
  String? hint, lastQuery;
  // Text we wrote ourselves must not trigger a new search.
  String? filled;
  double zoom = 5.2;

  bool get pinned => widget.latitude != null && widget.longitude != null;

  @override
  void initState() {
    super.initState();
    filled = widget.address.text;
    widget.address.addListener(_typed);
    if (pinned) zoom = 17;
  }

  @override
  void dispose() {
    widget.address.removeListener(_typed);
    typing?.cancel();
    settling?.cancel();
    map.dispose();
    super.dispose();
  }

  void _typed() {
    final text = widget.address.text.trim();
    if (text == filled?.trim()) return;
    filled = null;
    typing?.cancel();
    if (text.length < 3) {
      if (suggestions.isNotEmpty) setState(() => suggestions = const []);
      return;
    }
    typing = Timer(const Duration(milliseconds: 450), () => _search(text));
  }

  Future<void> _search(String text) async {
    if (!mounted || text == lastQuery) return;
    lastQuery = text;
    setState(() => searching = true);
    try {
      final center = pinned
          ? LatLng(widget.latitude!, widget.longitude!)
          : (zoom >= 11 ? map.camera.center : null);
      final found = await ref
          .read(geoRepositoryProvider)
          .suggest(text, nearLat: center?.latitude, nearLng: center?.longitude);
      if (!mounted || widget.address.text.trim() != text) return;
      setState(() {
        suggestions = found;
        hint = found.isEmpty
            ? 'Chưa thấy gợi ý phù hợp. Bạn vẫn có thể nhập tay và ghim trên bản đồ.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          suggestions = const [];
          hint = 'Chưa tải được gợi ý địa chỉ. Bạn vẫn có thể nhập tay.';
        });
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void _fill(String text) {
    filled = text;
    widget.address.text = text;
    widget.address.selection = TextSelection.collapsed(offset: text.length);
  }

  void _choose(GeoPlace place) {
    _fill(place.address);
    setState(() {
      suggestions = const [];
      nearPin = null;
      hint = null;
      zoom = 17;
    });
    widget.onPin(place.latitude, place.longitude);
    map.move(LatLng(place.latitude, place.longitude), 17);
  }

  void _moved(MapCamera camera, bool hasGesture) {
    zoom = camera.zoom;
    if (!hasGesture || !widget.enabled) return;
    settling?.cancel();
    settling = Timer(const Duration(milliseconds: 700), () => _settled(camera));
  }

  Future<void> _settled(MapCamera camera) async {
    if (!mounted) return;
    if (camera.zoom < _pinZoom) {
      setState(() {
        nearPin = null;
        hint = 'Phóng to bản đồ thêm để ghim chính xác vị trí nhận hàng.';
      });
      return;
    }
    final at = camera.center;
    widget.onPin(at.latitude, at.longitude);
    await _lookup(at);
  }

  Future<void> _lookup(LatLng at) async {
    setState(() {
      resolving = true;
      hint = null;
    });
    try {
      final place = await ref
          .read(geoRepositoryProvider)
          .reverse(at.latitude, at.longitude);
      if (!mounted) return;
      // Ignore a late answer for a spot the shopper has already left.
      if (widget.latitude != at.latitude || widget.longitude != at.longitude) {
        return;
      }
      setState(() => nearPin = place);
    } catch (_) {
      if (mounted) setState(() => nearPin = null);
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Future<void> _locate() async {
    setState(() {
      locating = true;
      hint = null;
    });
    final here = await currentLocation();
    if (!mounted) return;
    setState(() => locating = false);
    if (here == null) {
      setState(
        () => hint =
            'Không lấy được vị trí hiện tại. Hãy cho phép trình duyệt truy cập vị trí, hoặc kéo bản đồ để ghim.',
      );
      return;
    }
    final at = LatLng(here.latitude, here.longitude);
    zoom = 17;
    map.move(at, 17);
    widget.onPin(at.latitude, at.longitude);
    await _lookup(at);
  }

  void _unpin() {
    widget.onPin(null, null);
    setState(() => nearPin = null);
  }

  @override
  Widget build(BuildContext context) {
    final start = pinned
        ? LatLng(widget.latitude!, widget.longitude!)
        : _vietnam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (searching)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (suggestions.isNotEmpty) _Suggestions(suggestions, onPick: _choose),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Ghim vị trí giao hàng',
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (pinned)
              TextButton.icon(
                onPressed: widget.enabled ? _unpin : null,
                icon: const Icon(Icons.location_off_outlined, size: 18),
                label: const Text('Bỏ ghim'),
              ),
          ],
        ),
        const Text(
          'Kéo bản đồ để mũi ghim chỉ đúng cổng nhà hoặc toà nhà. Không bắt buộc, nhưng giúp giao hàng nhanh và chính xác hơn.',
          style: T.small,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: T.radius,
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: start,
                    initialZoom: zoom,
                    minZoom: 4,
                    maxZoom: 19,
                    interactionOptions: InteractionOptions(
                      flags: widget.enabled
                          ? InteractiveFlag.all & ~InteractiveFlag.rotate
                          : InteractiveFlag.none,
                    ),
                    onPositionChanged: _moved,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: BrandConfig.mapTileUrl,
                      retinaMode: RetinaMode.isHighDensity(context),
                      userAgentPackageName: 'vn.wearly.shop',
                      maxNativeZoom: 20,
                    ),
                  ],
                ),
                // Required credit for the map data; shrinks on narrow screens.
                Positioned(
                  left: 0,
                  bottom: 0,
                  right: 64,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        color: const Color(0xCCFFFFFF),
                        child: Text(
                          BrandConfig.mapAttribution,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.small.copyWith(fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                ),
                // The pin stays centred; its tip marks the delivery spot.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -18),
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: pinned ? T.accent : T.muted,
                        shadows: const [
                          Shadow(blurRadius: 6, color: Color(0x55000000)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Material(
                    color: T.surface,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'Dùng vị trí hiện tại của tôi',
                      onPressed: widget.enabled && !locating ? _locate : null,
                      icon: locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, color: T.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              pinned ? Icons.check_circle : Icons.info_outline,
              size: 16,
              color: pinned ? T.success : T.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pinned
                    ? 'Đã ghim vị trí nhận hàng.'
                    : 'Chưa ghim vị trí trên bản đồ.',
                style: T.small.copyWith(color: pinned ? T.success : T.muted),
              ),
            ),
          ],
        ),
        if (resolving)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Đang tìm địa chỉ tại vị trí ghim…', style: T.small),
          ),
        if (nearPin != null &&
            nearPin!.address.trim() != widget.address.text.trim())
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: T.soft, borderRadius: T.radius),
            child: Row(
              children: [
                const Icon(Icons.place_outlined, color: T.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Địa chỉ tại vị trí ghim', style: T.small),
                      Text(
                        nearPin!.address,
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.enabled
                      ? () {
                          _fill(nearPin!.address);
                          setState(() => suggestions = const []);
                        }
                      : null,
                  child: const Text('Dùng địa chỉ này'),
                ),
              ],
            ),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(hint!, style: T.small),
          ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions(this.places, {required this.onPick});
  final List<GeoPlace> places;
  final void Function(GeoPlace) onPick;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Material(
      color: T.surface,
      elevation: 3,
      shadowColor: const Color(0x33000000),
      shape: const RoundedRectangleBorder(
        borderRadius: T.radius,
        side: BorderSide(color: T.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < places.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, color: T.accent),
              title: Text(
                places[i].title,
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: places[i].subtitle.isEmpty
                  ? null
                  : Text(places[i].subtitle, style: T.small),
              onTap: () => onPick(places[i]),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Gợi ý từ OpenStreetMap', style: T.small),
            ),
          ),
        ],
      ),
    ),
  );
}
