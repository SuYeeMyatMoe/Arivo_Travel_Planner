import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/models/models.dart';
import '../../core/theme/arivo_theme.dart';

/// The day on the map: the Route Thread (dashed, day colour) through numbered stops. Camera eases to each day.
/// Straight segments are an honest simplification — legs are labelled EST. in the spine.
class TripMap extends StatefulWidget {
  const TripMap({super.key, required this.day, this.ink = false, this.focus, this.bottomPadding = 320});
  final ItineraryDay day;
  final bool ink;
  final ItineraryItem? focus;
  final double bottomPadding;

  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  MapLibreMapController? _map;
  bool _styleReady = false, _preparing = false;
  int _attempts = 0;
  Size _size = Size.zero;

  /// English labels everywhere (the base style shows local + Latin names), then the day's route.
  /// Retries because the style-loaded signal can arrive before, after, or (on web, while tiles stream) long after the map.
  Future<void> _prepare() async {
    final map = _map;
    if (map == null || !mounted || _styleReady || _preparing) return;
    _preparing = true;
    try {
      await map.setMapLanguage('en');
      await _draw();
      _styleReady = true;
    } catch (e) {
      debugPrint('TripMap: style not ready yet ($e)');
      if (++_attempts < 15) Future.delayed(const Duration(milliseconds: 600), _prepare);
    } finally {
      _preparing = false;
    }
  }

  @override
  void didUpdateWidget(TripMap old) {
    super.didUpdateWidget(old);
    if (_styleReady &&
        (old.day.index != widget.day.index ||
            old.day.items.length != widget.day.items.length ||
            old.day.items.firstOrNull?.start != widget.day.items.firstOrNull?.start)) {
      _draw();
    }
    if (_styleReady && widget.focus != null && widget.focus?.id != old.focus?.id) {
      _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(widget.focus!.lat, widget.focus!.lon), 15.5), duration: const Duration(milliseconds: 700));
    }
  }

  Map<String, dynamic> _geojson(Color color) {
    final items = widget.day.items.where((i) => i.lat != 0 && i.lon != 0).toList();
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return {
      'type': 'FeatureCollection',
      'features': [
        if (items.length > 1)
          {
            'type': 'Feature',
            'id': 'route',
            'properties': {'kind': 'route', 'color': hex},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final i in items) [i.lon, i.lat],
              ],
            },
          },
        for (var n = 0; n < items.length; n++)
          {
            'type': 'Feature',
            'id': 'stop$n',
            'properties': {'kind': 'stop', 'n': '${n + 1}', 'name': items[n].name, 'color': hex, 'booked': items[n].isBooked},
            'geometry': {
              'type': 'Point',
              'coordinates': [items[n].lon, items[n].lat],
            },
          },
      ],
    };
  }

  Future<void> _draw() async {
    final map = _map;
    if (map == null) return;
    final color = context.palette.route(widget.day.routeColor);
    final data = _geojson(color);
    final ids = await map.getLayerIds();
    if (!ids.contains('arivo-route')) {
      await map.addGeoJsonSource('arivo-day', data);
      await map.addLineLayer(
        'arivo-day',
        'arivo-route-glow',
        const LineLayerProperties(lineColor: ['get', 'color'], lineWidth: 10, lineOpacity: 0.18, lineBlur: 4),
        filter: [
          '==',
          ['get', 'kind'],
          'route',
        ],
      );
      await map.addLineLayer(
        'arivo-day',
        'arivo-route',
        const LineLayerProperties(lineColor: ['get', 'color'], lineWidth: 3.5, lineDasharray: [2, 1.4], lineCap: 'round'),
        filter: [
          '==',
          ['get', 'kind'],
          'route',
        ],
      );
      await map.addCircleLayer(
        'arivo-day',
        'arivo-stops',
        CircleLayerProperties(circleRadius: 11, circleColor: '#FFFFFF', circleStrokeColor: ['get', 'color'], circleStrokeWidth: 3),
        filter: [
          '==',
          ['get', 'kind'],
          'stop',
        ],
      );
      await map.addSymbolLayer(
        'arivo-day',
        'arivo-stop-n',
        const SymbolLayerProperties(textField: ['get', 'n'], textSize: 12, textAllowOverlap: true, textFont: ['Noto Sans Bold']),
        filter: [
          '==',
          ['get', 'kind'],
          'stop',
        ],
      );
    } else {
      await map.setGeoJsonSource('arivo-day', data);
    }
    _fit();
  }

  void _fit() {
    final items = widget.day.items.where((i) => i.lat != 0).toList();
    if (items.isEmpty) return;
    var s = items.first.lat, n = s, w = items.first.lon, e = w;
    for (final i in items) {
      s = math.min(s, i.lat);
      n = math.max(n, i.lat);
      w = math.min(w, i.lon);
      e = math.max(e, i.lon);
    }
    final pad = 0.004;
    // Padding must leave room for the route, or MapLibre refuses to fit (short windows, landscape phones).
    final h = _size.height, w0 = _size.width;
    if (h < 120 || w0 < 120) return;
    final top = math.min(90.0, h * 0.12), bottom = math.min(widget.bottomPadding, h * 0.45), side = math.min(36.0, w0 * 0.1);
    _map?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(s - pad, w - pad), northeast: LatLng(n + pad, e + pad)),
        left: side,
        top: top,
        right: side,
        bottom: bottom,
      ),
      duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.day.items.isNotEmpty ? widget.day.items.first : null;
    return Semantics(
      label: 'Map of ${widget.day.title}: ${widget.day.items.length} stops. The same stops are listed below.',
      child: LayoutBuilder(
        builder: (context, box) {
          _size = box.biggest;
          return MapLibreMap(
            styleString: ArivoConfig.mapStylePaper,
            initialCameraPosition: CameraPosition(target: first == null ? const LatLng(35.68, 139.76) : LatLng(first.lat, first.lon), zoom: 12.5),
            onMapCreated: (c) {
              _map = c;
              Future.delayed(const Duration(milliseconds: 1200), _prepare);
            },
            onStyleLoadedCallback: _prepare,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
          );
        },
      ),
    );
  }
}

/// Visible map attribution (OpenStreetMap ODbL + OpenFreeMap/OpenMapTiles). Tappable to the licence page.
class MapCredit extends StatelessWidget {
  const MapCredit({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.type, p = context.palette;
    return Semantics(
      link: true,
      label: 'Map data OpenStreetMap contributors, tiles OpenFreeMap. Opens the copyright page.',
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication),
        child: Container(
          margin: const EdgeInsets.only(top: 6, left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
          child: Text('© OpenStreetMap · OpenFreeMap', style: t.caption.copyWith(fontSize: 11, color: p.text)),
        ),
      ),
    );
  }
}
