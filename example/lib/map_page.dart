import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tracelet/tracelet.dart' as tl;

// ─────────────────────────────────────────────────────────────────────────────
// Track point with speed/heading/activity for rich trail visualization
// ─────────────────────────────────────────────────────────────────────────────

class _TrackPoint {
  const _TrackPoint({
    required this.position,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.isMoving,
    required this.timestamp,
    this.activityType = tl.ActivityType.unknown,
  });

  final LatLng position;
  final double speed; // m/s
  final double heading; // degrees
  final double accuracy; // meters
  final bool isMoving;
  final String timestamp;
  final tl.ActivityType activityType;

  double get speedKmh => speed * 3.6;

  /// Speed → color: grey(still) → green(walk) → yellow(jog) → orange(bike) → red(drive).
  Color get speedColor {
    if (speed < 0.5) return Colors.grey;
    if (speed < 2.0) return Colors.green;
    if (speed < 4.0) return Colors.lightGreen;
    if (speed < 8.0) return Colors.yellow.shade700;
    if (speed < 15.0) return Colors.orange;
    return Colors.red;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MapPage — comprehensive live map with all Tracelet features
// ─────────────────────────────────────────────────────────────────────────────

/// Live map using OpenStreetMap tiles (free, no API key, works everywhere).
///
/// Features:
/// - Current location marker with heading indicator
/// - Speed-colored route trail (green→yellow→orange→red by velocity)
/// - Breadcrumb dots along the path
/// - Geofence visualization (circles + polygons) — tap for details
/// - Trip overlay with start/end markers and waypoint path
/// - Long-press to add circular geofence at any point
/// - Polygon drawing mode (tap vertices, then confirm)
/// - Route statistics bar (distance, speed, max, points)
/// - Historical stored locations overlay from DB
/// - Layer toggle menu
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final List<_TrackPoint> _trail = [];
  final List<StreamSubscription<Object?>> _subs = [];

  LatLng? _currentPosition;
  double _currentAccuracy = 0;
  double _currentHeading = 0;
  double _currentSpeed = 0;
  bool _isMoving = false;
  bool _followMode = true;

  // Smooth position animation
  AnimationController? _posAnimController;
  LatLng? _animStartPos;
  LatLng? _animEndPos;
  LatLng? _displayPosition; // Interpolated position shown on map

  // Layer toggles
  bool _showTrail = true;
  bool _showGeofences = true;
  bool _showBreadcrumbs = true;
  bool _showAccuracyCircle = true;
  bool _showSpeedColors = true;
  bool _showHistorical = false;
  bool _showStatusOverlay = true;
  bool _showEventLog = false;

  // Feature status
  bool _kalmanEnabled = false;
  bool _isTracking = false;

  // Geofences
  List<tl.Geofence> _geofences = [];

  // Geofence events
  final List<_MapEvent> _eventLog = [];
  String? _flashGeofenceId; // Briefly highlight a geofence on event

  // Polygon drawing
  bool _polygonDrawMode = false;
  final List<LatLng> _polygonVertices = [];

  // Trip
  final List<LatLng> _tripWaypoints = [];
  LatLng? _tripStart;
  LatLng? _tripEnd;
  tl.TripEvent? _lastTrip;
  bool _tripInProgress = false;
  DateTime? _tripStartTime;
  double _tripDistance = 0;
  int _tripWaypointCount = 0;

  // Live trip trail (drawn as waypoints come in during active trip)
  final List<LatLng> _liveTripTrail = [];

  // Historical
  List<tl.Location> _historicalLocations = [];

  // Stats
  double _totalDistance = 0;
  double _maxSpeed = 0;
  int _pointCount = 0;

  // Timer for active trip elapsed display
  Timer? _tripTimer;

  @override
  void initState() {
    super.initState();
    _subscribeEvents();
    _loadInitialState();
  }

  @override
  void dispose() {
    _tripTimer?.cancel();
    _posAnimController?.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _mapController.dispose();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────────────────────────────

  Future<void> _loadInitialState() async {
    try {
      final loc = await tl.Tracelet.getLastKnownLocation();
      if (loc != null) {
        final pos = LatLng(loc.coords.latitude, loc.coords.longitude);
        setState(() {
          _currentPosition = pos;
          _currentAccuracy = loc.coords.accuracy;
          _currentHeading = loc.coords.heading;
          _currentSpeed = loc.coords.speed;
          _trail.add(
            _TrackPoint(
              position: pos,
              speed: loc.coords.speed,
              heading: loc.coords.heading,
              accuracy: loc.coords.accuracy,
              isMoving: loc.isMoving,
              timestamp: loc.timestamp,
              activityType: loc.activity.type,
            ),
          );
        });
        _mapController.move(pos, 16);
      }
      final fences = await tl.Tracelet.getGeofences();
      final state = await tl.Tracelet.getState();
      setState(() {
        _geofences = fences;
        _isMoving = state.isMoving;
        _isTracking = state.enabled;
        _totalDistance = state.odometer;
        _kalmanEnabled = tl.Tracelet.isKalmanFilterEnabled;
      });
    } catch (_) {}
  }

  // ── Subscriptions ──────────────────────────────────────────────────────

  void _subscribeEvents() {
    _subs.add(
      tl.Tracelet.onLocation((loc) {
        final pos = LatLng(loc.coords.latitude, loc.coords.longitude);
        setState(() {
          _currentPosition = pos;
          _currentAccuracy = loc.coords.accuracy;
          _currentHeading = loc.coords.heading;
          _currentSpeed = loc.coords.speed;
          _trail.add(
            _TrackPoint(
              position: pos,
              speed: loc.coords.speed,
              heading: loc.coords.heading,
              accuracy: loc.coords.accuracy,
              isMoving: loc.isMoving,
              timestamp: loc.timestamp,
              activityType: loc.activity.type,
            ),
          );
          _pointCount = _trail.length;
          _totalDistance = loc.odometer;
          if (loc.coords.speed > _maxSpeed) _maxSpeed = loc.coords.speed;
          if (_trail.length > 1000) _trail.removeAt(0);

          // Update active trip stats and live trail
          if (_tripInProgress) {
            _tripWaypointCount++;
            _liveTripTrail.add(pos);
            if (_trail.length >= 2) {
              final prev = _trail[_trail.length - 2].position;
              final curr = _trail.last.position;
              final d = const Distance();
              _tripDistance += d.as(LengthUnit.Meter, prev, curr);
            }
          }
        });

        // Animate position smoothly
        _animateToPosition(pos);

        if (_followMode) {
          _mapController.move(pos, _mapController.camera.zoom);
        }
      }),
    );

    _subs.add(
      tl.Tracelet.onMotionChange((loc) {
        final pos = LatLng(loc.coords.latitude, loc.coords.longitude);
        setState(() {
          _isMoving = loc.isMoving;
          _currentPosition = pos;

          // Track active trip in-progress
          if (loc.isMoving && !_tripInProgress) {
            _tripInProgress = true;
            _tripStartTime = DateTime.now();
            _tripDistance = 0;
            _tripWaypointCount = 0;
            _liveTripTrail.clear();
            _liveTripTrail.add(pos);
            _tripTimer?.cancel();
            _tripTimer = Timer.periodic(
              const Duration(seconds: 1),
              (_) => setState(() {}), // Refresh elapsed time display
            );
          } else if (!loc.isMoving && _tripInProgress) {
            _tripInProgress = false;
            _tripTimer?.cancel();
            _tripTimer = null;
          }
        });

        // Log motion change
        _addMapEvent(
          _MapEvent(
            icon: loc.isMoving ? Icons.directions_walk : Icons.pause_circle,
            color: loc.isMoving ? Colors.blue : Colors.orange,
            title: loc.isMoving ? 'Started Moving' : 'Stopped',
            subtitle:
                '${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)}',
            time: DateTime.now(),
          ),
        );

        // Animate to new position
        _animateToPosition(pos);

        if (_followMode) {
          _mapController.move(pos, _mapController.camera.zoom);
        }
      }),
    );

    _subs.add(
      tl.Tracelet.onGeofence((event) async {
        // Log the geofence event
        _addMapEvent(
          _MapEvent(
            icon: event.action == tl.GeofenceAction.enter
                ? Icons.login
                : event.action == tl.GeofenceAction.exit
                ? Icons.logout
                : Icons.timer,
            color: event.action == tl.GeofenceAction.enter
                ? Colors.green
                : event.action == tl.GeofenceAction.exit
                ? Colors.red
                : Colors.amber,
            title: '${event.action.name.toUpperCase()} ${event.identifier}',
            subtitle:
                '${event.location.coords.latitude.toStringAsFixed(5)}, '
                '${event.location.coords.longitude.toStringAsFixed(5)}',
            time: DateTime.now(),
          ),
        );

        // Flash the geofence briefly
        setState(() => _flashGeofenceId = event.identifier);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _flashGeofenceId = null);
        });

        // Refresh geofence list
        try {
          final fences = await tl.Tracelet.getGeofences();
          setState(() => _geofences = fences);
        } catch (_) {}
      }),
    );

    _subs.add(
      tl.Tracelet.onTrip((trip) {
        setState(() {
          _lastTrip = trip;
          _tripWaypoints.clear();
          for (final wp in trip.waypoints) {
            _tripWaypoints.add(LatLng(wp.coords.latitude, wp.coords.longitude));
          }
          if (trip.startLocation.coords.latitude != 0) {
            _tripStart = LatLng(
              trip.startLocation.coords.latitude,
              trip.startLocation.coords.longitude,
            );
          }
          if (trip.stopLocation.coords.latitude != 0) {
            _tripEnd = LatLng(
              trip.stopLocation.coords.latitude,
              trip.stopLocation.coords.longitude,
            );
          }

          // Trip ended — clear live trail
          _liveTripTrail.clear();
        });

        // Log trip completed
        _addMapEvent(
          _MapEvent(
            icon: Icons.route,
            color: Colors.green,
            title: 'Trip Completed',
            subtitle:
                '${(trip.distance / 1000).toStringAsFixed(2)} km in '
                '${(trip.duration / 60).toStringAsFixed(1)} min',
            time: DateTime.now(),
          ),
        );
      }),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Smoothly animate the position marker from current to new position.
  void _animateToPosition(LatLng target) {
    _animStartPos = _displayPosition ?? _currentPosition ?? target;
    _animEndPos = target;

    _posAnimController?.dispose();
    _posAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _posAnimController!.addListener(() {
      final t = _posAnimController!.value;
      final start = _animStartPos!;
      final end = _animEndPos!;
      setState(() {
        _displayPosition = LatLng(
          start.latitude + (end.latitude - start.latitude) * t,
          start.longitude + (end.longitude - start.longitude) * t,
        );
      });
    });

    _posAnimController!.forward();
  }

  /// Add an event to the event log (max 50 entries).
  void _addMapEvent(_MapEvent event) {
    setState(() {
      _eventLog.insert(0, event);
      if (_eventLog.length > 50) _eventLog.removeLast();
    });
  }

  /// Delete a geofence by identifier.
  Future<void> _deleteGeofence(String identifier) async {
    try {
      await tl.Tracelet.removeGeofence(identifier);
      final fences = await tl.Tracelet.getGeofences();
      setState(() => _geofences = fences);
      _addMapEvent(
        _MapEvent(
          icon: Icons.delete,
          color: Colors.red,
          title: 'Deleted $identifier',
          subtitle: 'Geofence removed',
          time: DateTime.now(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geofence "$identifier" deleted'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────

  void _centerOnLocation() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 16);
      setState(() => _followMode = true);
    }
  }

  void _fitTrail() {
    final points = _trail.map((t) => t.position).toList();
    if (points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(50),
      ),
    );
    setState(() => _followMode = false);
  }

  Future<void> _addCircularGeofenceAt(LatLng pos) async {
    try {
      final id = 'map_geo_${DateTime.now().millisecondsSinceEpoch}';
      await tl.Tracelet.addGeofence(
        tl.Geofence(
          identifier: id,
          latitude: pos.latitude,
          longitude: pos.longitude,
          radius: 200,
          notifyOnEntry: true,
          notifyOnExit: true,
          notifyOnDwell: true,
          loiteringDelay: 30000,
        ),
      );
      final fences = await tl.Tracelet.getGeofences();
      setState(() => _geofences = fences);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geofence "$id" added (r=200m)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _finishPolygonDrawing() async {
    if (_polygonVertices.length < 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Need at least 3 vertices')));
      return;
    }
    try {
      final id = 'map_poly_${DateTime.now().millisecondsSinceEpoch}';
      double latSum = 0, lngSum = 0;
      for (final v in _polygonVertices) {
        latSum += v.latitude;
        lngSum += v.longitude;
      }
      await tl.Tracelet.addGeofence(
        tl.Geofence(
          identifier: id,
          latitude: latSum / _polygonVertices.length,
          longitude: lngSum / _polygonVertices.length,
          radius: 0,
          notifyOnEntry: true,
          notifyOnExit: true,
          vertices: _polygonVertices
              .map((v) => [v.latitude, v.longitude])
              .toList(),
        ),
      );
      final fences = await tl.Tracelet.getGeofences();
      setState(() {
        _geofences = fences;
        _polygonDrawMode = false;
        _polygonVertices.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Polygon "$id" created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _loadHistoricalLocations() async {
    try {
      final locs = await tl.Tracelet.getLocations();
      setState(() {
        _historicalLocations = locs;
        _showHistorical = true;
      });
      if (locs.isNotEmpty) {
        final points = locs
            .map((l) => LatLng(l.coords.latitude, l.coords.longitude))
            .toList();
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(50),
          ),
        );
        setState(() => _followMode = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${locs.length} stored locations'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  void _showGeofenceDetails(tl.Geofence gf) {
    final isPolygon = gf.vertices.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPolygon ? Icons.hexagon_outlined : Icons.circle_outlined,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gf.identifier,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Delete geofence',
                  onPressed: () async {
                    await tl.Tracelet.removeGeofence(gf.identifier);
                    final fences = await tl.Tracelet.getGeofences();
                    setState(() => _geofences = fences);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const Divider(),
            _DetailRow(
              'Type',
              isPolygon ? 'Polygon (${gf.vertices.length} vertices)' : 'Circle',
            ),
            _DetailRow(
              'Center',
              '${gf.latitude.toStringAsFixed(5)}, '
                  '${gf.longitude.toStringAsFixed(5)}',
            ),
            if (!isPolygon)
              _DetailRow('Radius', '${gf.radius.toStringAsFixed(0)}m'),
            _DetailRow('Entry', gf.notifyOnEntry ? 'Yes' : 'No'),
            _DetailRow('Exit', gf.notifyOnExit ? 'Yes' : 'No'),
            _DetailRow('Dwell', gf.notifyOnDwell ? 'Yes' : 'No'),
            if (gf.notifyOnDwell)
              _DetailRow('Loitering', '${gf.loiteringDelay}ms'),
            if (isPolygon) ...[
              const SizedBox(height: 4),
              Text(
                'Vertices',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor),
              ),
              for (int i = 0; i < gf.vertices.length; i++)
                _DetailRow(
                  '  #${i + 1}',
                  gf.vertices[i].length >= 2
                      ? '${gf.vertices[i][0].toStringAsFixed(5)}, '
                            '${gf.vertices[i][1].toStringAsFixed(5)}'
                      : 'invalid',
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddGeofenceMenu(LatLng pos) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Geofence',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)}',
                style: TextStyle(
                  color: Theme.of(ctx).hintColor,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.circle_outlined,
                  color: Colors.orange,
                ),
                title: const Text('Circular Geofence (200m)'),
                subtitle: const Text('Entry + exit + dwell monitoring'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addCircularGeofenceAt(pos);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.hexagon_outlined,
                  color: Colors.deepOrange,
                ),
                title: const Text('Start Polygon Drawing'),
                subtitle: const Text('Tap map to place vertices'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _polygonDrawMode = true;
                    _polygonVertices.clear();
                    _polygonVertices.add(pos);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Map layers ─────────────────────────────────────────────────────────

  TileLayer _buildTileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.roastedoats.tracelet_example',
      maxZoom: 19,
    );
  }

  PolylineLayer _buildSpeedTrailLayer() {
    if (!_showTrail || _trail.length < 2) {
      return const PolylineLayer(polylines: []);
    }
    if (!_showSpeedColors) {
      return PolylineLayer(
        polylines: [
          Polyline(
            points: _trail.map((t) => t.position).toList(),
            color: Colors.blue.withAlpha(180),
            strokeWidth: 3,
          ),
        ],
      );
    }
    // Per-segment speed coloring
    final polylines = <Polyline>[];
    for (int i = 0; i < _trail.length - 1; i++) {
      polylines.add(
        Polyline(
          points: [_trail[i].position, _trail[i + 1].position],
          color: _trail[i + 1].speedColor.withAlpha(200),
          strokeWidth: 4,
        ),
      );
    }
    return PolylineLayer(polylines: polylines);
  }

  MarkerLayer _buildBreadcrumbs() {
    if (!_showBreadcrumbs || _trail.isEmpty) {
      return const MarkerLayer(markers: []);
    }
    final step = (_trail.length / 50).ceil().clamp(1, 20);
    final markers = <Marker>[];
    for (int i = 0; i < _trail.length; i += step) {
      final pt = _trail[i];
      markers.add(
        Marker(
          point: pt.position,
          width: 8,
          height: 8,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _showSpeedColors
                  ? pt.speedColor.withAlpha(180)
                  : Colors.blue.withAlpha(120),
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }

  List<Widget> _buildHistoricalLayers() {
    if (!_showHistorical || _historicalLocations.isEmpty) return [];
    final points = _historicalLocations
        .map((l) => LatLng(l.coords.latitude, l.coords.longitude))
        .toList();
    final step = (points.length / 30).ceil().clamp(1, 50);
    final markers = <Marker>[];
    for (int i = 0; i < points.length; i += step) {
      markers.add(
        Marker(
          point: points[i],
          width: 6,
          height: 6,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purple.withAlpha(150),
              border: Border.all(color: Colors.white, width: 0.5),
            ),
          ),
        ),
      );
    }
    return [
      PolylineLayer(
        polylines: [
          Polyline(
            points: points,
            color: Colors.purple.withAlpha(150),
            strokeWidth: 2,
            pattern: const StrokePattern.dotted(),
          ),
        ],
      ),
      MarkerLayer(markers: markers),
    ];
  }

  PolylineLayer _buildTripLayer() {
    return PolylineLayer(
      polylines: [
        if (_tripWaypoints.length >= 2)
          Polyline(
            points: _tripWaypoints,
            color: Colors.green.withAlpha(200),
            strokeWidth: 4,
            pattern: const StrokePattern.dotted(),
          ),
        // Live trip trail drawn in real-time
        if (_tripInProgress && _liveTripTrail.length >= 2)
          Polyline(points: _liveTripTrail, color: Colors.green, strokeWidth: 3),
      ],
    );
  }

  MarkerLayer _buildTripMarkers() {
    final markers = <Marker>[];
    if (_tripStart != null) {
      markers.add(
        Marker(
          point: _tripStart!,
          width: 40,
          height: 40,
          child: const _TripPinWidget(
            icon: Icons.trip_origin,
            color: Colors.green,
            label: 'START',
          ),
        ),
      );
    }
    if (_tripEnd != null) {
      markers.add(
        Marker(
          point: _tripEnd!,
          width: 40,
          height: 40,
          child: const _TripPinWidget(
            icon: Icons.flag,
            color: Colors.red,
            label: 'END',
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }

  MarkerLayer _buildCurrentLocationMarker() {
    final pos = _displayPosition ?? _currentPosition;
    if (pos == null) return const MarkerLayer(markers: []);
    return MarkerLayer(
      markers: [
        Marker(
          point: pos,
          width: 48,
          height: 48,
          child: _LocationMarkerWidget(
            isMoving: _isMoving,
            heading: _currentHeading,
            speed: _currentSpeed,
          ),
        ),
      ],
    );
  }

  CircleLayer _buildAccuracyCircle() {
    if (_currentPosition == null ||
        _currentAccuracy <= 0 ||
        !_showAccuracyCircle) {
      return const CircleLayer(circles: []);
    }
    return CircleLayer(
      circles: [
        CircleMarker(
          point: _currentPosition!,
          radius: _currentAccuracy,
          useRadiusInMeter: true,
          color: Colors.blue.withAlpha(20),
          borderColor: Colors.blue.withAlpha(60),
          borderStrokeWidth: 1,
        ),
      ],
    );
  }

  List<Widget> _buildGeofenceLayers() {
    if (!_showGeofences) return [];
    final circles = <CircleMarker>[];
    final polygons = <Polygon>[];
    for (final gf in _geofences) {
      final isFlashing = _flashGeofenceId == gf.identifier;
      final fillColor = isFlashing
          ? Colors.green.withAlpha(80)
          : Colors.orange.withAlpha(40);
      final borderColor = isFlashing ? Colors.green : Colors.orange;
      final borderWidth = isFlashing ? 4.0 : 2.0;

      final isPolygon = gf.vertices.isNotEmpty && gf.vertices.first.length >= 2;
      if (isPolygon) {
        final points = gf.vertices
            .where((v) => v.length >= 2)
            .map((v) => LatLng(v[0], v[1]))
            .toList();
        if (points.length >= 3) {
          polygons.add(
            Polygon(
              points: points,
              color: fillColor,
              borderColor: borderColor,
              borderStrokeWidth: borderWidth,
              label: gf.identifier,
              labelStyle: TextStyle(
                color: isFlashing ? Colors.green.shade800 : Colors.deepOrange,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
      } else {
        circles.add(
          CircleMarker(
            point: LatLng(gf.latitude, gf.longitude),
            radius: gf.radius,
            useRadiusInMeter: true,
            color: fillColor,
            borderColor: borderColor,
            borderStrokeWidth: borderWidth,
          ),
        );
      }
    }
    return [
      if (circles.isNotEmpty) CircleLayer(circles: circles),
      if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
    ];
  }

  MarkerLayer _buildGeofenceTapTargets() {
    if (!_showGeofences) return const MarkerLayer(markers: []);
    final markers = <Marker>[];
    for (final gf in _geofences) {
      markers.add(
        Marker(
          point: LatLng(gf.latitude, gf.longitude),
          width: 150,
          height: 28,
          child: GestureDetector(
            onTap: () => _showGeofenceDetails(gf),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _flashGeofenceId == gf.identifier
                      ? Colors.green.shade50
                      : Colors.white.withAlpha(220),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _flashGeofenceId == gf.identifier
                        ? Colors.green
                        : Colors.orange,
                    width: _flashGeofenceId == gf.identifier ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 4),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      gf.vertices.isNotEmpty
                          ? Icons.hexagon_outlined
                          : Icons.circle_outlined,
                      size: 12,
                      color: _flashGeofenceId == gf.identifier
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        gf.identifier,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _flashGeofenceId == gf.identifier
                              ? Colors.green.shade800
                              : Colors.deepOrange,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    GestureDetector(
                      onTap: () => _deleteGeofence(gf.identifier),
                      child: const Icon(
                        Icons.close,
                        size: 12,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }

  List<Widget> _buildPolygonDrawingLayers() {
    if (!_polygonDrawMode) return [];
    final layers = <Widget>[];

    // Vertex markers
    final markers = <Marker>[];
    for (int i = 0; i < _polygonVertices.length; i++) {
      markers.add(
        Marker(
          point: _polygonVertices[i],
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.deepOrange,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }
    layers.add(MarkerLayer(markers: markers));

    // Edge lines
    if (_polygonVertices.length >= 2) {
      layers.add(
        PolylineLayer(
          polylines: [
            Polyline(
              points: [..._polygonVertices, _polygonVertices.first],
              color: Colors.deepOrange.withAlpha(180),
              strokeWidth: 2,
              pattern: const StrokePattern.dotted(),
            ),
          ],
        ),
      );
    }

    // Fill preview
    if (_polygonVertices.length >= 3) {
      layers.add(
        PolygonLayer(
          polygons: [
            Polygon(
              points: _polygonVertices,
              color: Colors.deepOrange.withAlpha(30),
              borderColor: Colors.deepOrange,
              borderStrokeWidth: 2,
            ),
          ],
        ),
      );
    }

    return layers;
  }

  // ── Stats bar ──────────────────────────────────────────────────────────

  Widget _buildStatsBar() {
    final avgSpeed = _trail.isEmpty
        ? 0.0
        : _trail.map((t) => t.speed).reduce((a, b) => a + b) / _trail.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              icon: Icons.straighten,
              label: 'Distance',
              value: _totalDistance >= 1000
                  ? '${(_totalDistance / 1000).toStringAsFixed(2)} km'
                  : '${_totalDistance.toStringAsFixed(0)} m',
            ),
            _StatItem(
              icon: Icons.speed,
              label: 'Speed',
              value: '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h',
            ),
            _StatItem(
              icon: Icons.trending_up,
              label: 'Avg',
              value: '${(avgSpeed * 3.6).toStringAsFixed(1)} km/h',
            ),
            _StatItem(
              icon: Icons.bolt,
              label: 'Max',
              value: '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h',
            ),
            _StatItem(
              icon: Icons.pin_drop,
              label: 'Points',
              value: '$_pointCount',
            ),
          ],
        ),
      ),
    );
  }

  // ── Speed legend ───────────────────────────────────────────────────────

  Widget _buildSpeedLegend() {
    if (!_showSpeedColors || !_showTrail) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      bottom: 70,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(220),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 4),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Speed',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 2),
            _LegendItem(Colors.green, 'Walk <7 km/h'),
            _LegendItem(Colors.lightGreen, 'Jog 7-14 km/h'),
            _LegendItem(Color(0xFFEF6C00), 'Run 14-29 km/h'),
            _LegendItem(Colors.orange, 'Cycle 29-54 km/h'),
            _LegendItem(Colors.red, 'Drive >54 km/h'),
          ],
        ),
      ),
    );
  }

  // ── Status overlay (Kalman, tracking, motion, geofences) ──────────────

  Widget _buildStatusOverlay() {
    if (!_showStatusOverlay) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(230),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 6),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tracking status
            _StatusChip(
              icon: _isTracking ? Icons.gps_fixed : Icons.gps_off,
              label: _isTracking ? 'Tracking' : 'Stopped',
              color: _isTracking ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 4),
            // Motion state
            _StatusChip(
              icon: _isMoving ? Icons.directions_walk : Icons.pause_circle,
              label: _isMoving ? 'Moving' : 'Stationary',
              color: _isMoving ? Colors.blue : Colors.orange,
            ),
            const SizedBox(height: 4),
            // Kalman filter
            GestureDetector(
              onTap: _toggleKalmanFromMap,
              child: _StatusChip(
                icon: _kalmanEnabled ? Icons.blur_on : Icons.blur_off,
                label: 'Kalman: ${_kalmanEnabled ? "ON" : "OFF"}',
                color: _kalmanEnabled ? Colors.teal : Colors.grey,
                showToggle: true,
              ),
            ),
            const SizedBox(height: 4),
            // Geofence count
            _StatusChip(
              icon: Icons.fence,
              label: '${_geofences.length} Geofences',
              color: Colors.deepOrange,
            ),
            if (_currentPosition != null) ...[
              const SizedBox(height: 4),
              // Coordinates
              _StatusChip(
                icon: Icons.location_on,
                label:
                    '${_currentPosition!.latitude.toStringAsFixed(5)}, '
                    '${_currentPosition!.longitude.toStringAsFixed(5)}',
                color: Colors.indigo,
              ),
            ],
            if (_currentAccuracy > 0) ...[
              const SizedBox(height: 4),
              _StatusChip(
                icon: Icons.adjust,
                label: '~${_currentAccuracy.toStringAsFixed(0)}m accuracy',
                color: _currentAccuracy <= 10
                    ? Colors.green
                    : _currentAccuracy <= 30
                    ? Colors.orange
                    : Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Active trip in-progress card ──────────────────────────────────────

  Widget _buildActiveTripCard() {
    if (!_tripInProgress || _tripStartTime == null) {
      return const SizedBox.shrink();
    }
    final elapsed = DateTime.now().difference(_tripStartTime!);
    final mins = elapsed.inMinutes;
    final secs = elapsed.inSeconds % 60;
    return Positioned(
      top: 8,
      left: 8,
      child: Card(
        elevation: 4,
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'TRIP IN PROGRESS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${mins}m ${secs.toString().padLeft(2, '0')}s',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _tripDistance >= 1000
                    ? '${(_tripDistance / 1000).toStringAsFixed(2)} km'
                    : '${_tripDistance.toStringAsFixed(0)} m',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              Text(
                '$_tripWaypointCount waypoints',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Event log overlay ──────────────────────────────────────────────────

  Widget _buildEventLog() {
    if (!_showEventLog || _eventLog.isEmpty) return const SizedBox.shrink();
    return Positioned(
      bottom: 8,
      left: 8,
      right: 70,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 180),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(230),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 6),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.list_alt, size: 14, color: Colors.indigo),
                  const SizedBox(width: 4),
                  const Text(
                    'Events',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _eventLog.clear()),
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontSize: 10, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _eventLog.length > 10 ? 10 : _eventLog.length,
                itemBuilder: (_, i) {
                  final e = _eventLog[i];
                  final ago = DateTime.now().difference(e.time);
                  String agoStr;
                  if (ago.inSeconds < 60) {
                    agoStr = '${ago.inSeconds}s ago';
                  } else if (ago.inMinutes < 60) {
                    agoStr = '${ago.inMinutes}m ago';
                  } else {
                    agoStr = '${ago.inHours}h ago';
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        Icon(e.icon, size: 14, color: e.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: e.color,
                                ),
                              ),
                              Text(
                                e.subtitle,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          agoStr,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Toggle Kalman filter from map ─────────────────────────────────────

  Future<void> _toggleKalmanFromMap() async {
    try {
      final newValue = !_kalmanEnabled;
      await tl.Tracelet.setConfig(
        tl.Config(
          geo: tl.GeoConfig(
            filter: tl.LocationFilter(useKalmanFilter: newValue),
          ),
        ),
      );
      setState(() {
        _kalmanEnabled = newValue;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newValue
                  ? 'Kalman filter enabled — GPS smoothing active'
                  : 'Kalman filter disabled — raw GPS coordinates',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to toggle Kalman: $e')));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Live Map'),
            const SizedBox(width: 6),
            if (_isMoving)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'MOVING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'STILL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            if (_kalmanEnabled) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Kalman filter active',
                child: Icon(
                  Icons.blur_on,
                  size: 16,
                  color: Colors.teal.shade400,
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        actions: [
          // Status overlay toggle
          IconButton(
            tooltip: 'Toggle status overlay',
            icon: Icon(
              Icons.info_outline,
              color: _showStatusOverlay ? cs.primary : null,
            ),
            onPressed: () =>
                setState(() => _showStatusOverlay = !_showStatusOverlay),
          ),
          // Layer menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers),
            tooltip: 'Map layers',
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'trail':
                    _showTrail = !_showTrail;
                  case 'geofences':
                    _showGeofences = !_showGeofences;
                  case 'breadcrumbs':
                    _showBreadcrumbs = !_showBreadcrumbs;
                  case 'accuracy':
                    _showAccuracyCircle = !_showAccuracyCircle;
                  case 'speedColors':
                    _showSpeedColors = !_showSpeedColors;
                  case 'historical':
                    if (!_showHistorical) {
                      _loadHistoricalLocations();
                    } else {
                      _showHistorical = false;
                    }
                  case 'clearTrail':
                    _trail.clear();
                    _pointCount = 0;
                    _maxSpeed = 0;
                  case 'clearTrip':
                    _tripWaypoints.clear();
                    _tripStart = null;
                    _tripEnd = null;
                    _lastTrip = null;
                }
              });
            },
            itemBuilder: (_) => [
              _layerItem('trail', 'Route trail', Icons.timeline, _showTrail),
              _layerItem(
                'speedColors',
                'Speed colors',
                Icons.palette,
                _showSpeedColors,
              ),
              _layerItem(
                'breadcrumbs',
                'Breadcrumbs',
                Icons.more_horiz,
                _showBreadcrumbs,
              ),
              _layerItem('geofences', 'Geofences', Icons.fence, _showGeofences),
              _layerItem(
                'accuracy',
                'Accuracy circle',
                Icons.adjust,
                _showAccuracyCircle,
              ),
              _layerItem(
                'historical',
                'Stored locations',
                Icons.history,
                _showHistorical,
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clearTrail',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep, size: 20),
                  title: Text('Clear trail'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clearTrip',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, size: 20),
                  title: Text('Clear trip'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          // Fit trail
          IconButton(
            tooltip: 'Fit trail',
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _trail.length >= 2 ? _fitTrail : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Polygon draw banner
          if (_polygonDrawMode)
            MaterialBanner(
              content: Text(
                'Tap on the map to add vertices '
                '(${_polygonVertices.length} placed)',
              ),
              leading: const Icon(
                Icons.hexagon_outlined,
                color: Colors.deepOrange,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _polygonDrawMode = false;
                      _polygonVertices.clear();
                    });
                  },
                  child: const Text('Cancel'),
                ),
                if (_polygonVertices.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        setState(() => _polygonVertices.removeLast()),
                    child: const Text('Undo'),
                  ),
                if (_polygonVertices.length >= 3)
                  FilledButton(
                    onPressed: _finishPolygonDrawing,
                    child: const Text('Create'),
                  ),
              ],
            ),

          // Map
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _currentPosition ?? const LatLng(37.3382, -121.8863),
                    initialZoom: 16,
                    maxZoom: 19,
                    minZoom: 3,
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture) setState(() => _followMode = false);
                    },
                    onTap: _polygonDrawMode
                        ? (_, latLng) =>
                              setState(() => _polygonVertices.add(latLng))
                        : null,
                    onLongPress: !_polygonDrawMode
                        ? (_, latLng) => _showAddGeofenceMenu(latLng)
                        : null,
                  ),
                  children: [
                    _buildTileLayer(),
                    _buildAccuracyCircle(),
                    ..._buildGeofenceLayers(),
                    ..._buildHistoricalLayers(),
                    _buildSpeedTrailLayer(),
                    _buildBreadcrumbs(),
                    _buildTripLayer(),
                    _buildTripMarkers(),
                    ..._buildPolygonDrawingLayers(),
                    _buildGeofenceTapTargets(),
                    _buildCurrentLocationMarker(),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap'),
                    ),
                  ],
                ),
                _buildSpeedLegend(),
                _buildStatusOverlay(),
                _buildActiveTripCard(),
                _buildEventLog(),
                if (_lastTrip != null && !_tripInProgress)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 70,
                    child: _TripInfoCard(trip: _lastTrip!),
                  ),
              ],
            ),
          ),

          // Stats bar
          _buildStatsBar(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Event log toggle
          FloatingActionButton.small(
            heroTag: 'eventLog',
            backgroundColor: _showEventLog ? Colors.indigo : null,
            onPressed: () => setState(() => _showEventLog = !_showEventLog),
            child: Icon(
              Icons.list_alt,
              color: _showEventLog ? Colors.white : null,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          // Polygon draw toggle
          FloatingActionButton.small(
            heroTag: 'polygon',
            backgroundColor: _polygonDrawMode ? Colors.deepOrange : null,
            onPressed: () {
              setState(() {
                _polygonDrawMode = !_polygonDrawMode;
                if (!_polygonDrawMode) _polygonVertices.clear();
              });
            },
            child: Icon(
              Icons.hexagon_outlined,
              color: _polygonDrawMode ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 8),
          // Follow
          FloatingActionButton.small(
            heroTag: 'follow',
            backgroundColor: _followMode ? cs.primaryContainer : null,
            onPressed: _centerOnLocation,
            child: Icon(_followMode ? Icons.gps_fixed : Icons.gps_not_fixed),
          ),
          const SizedBox(height: 8),
          // Refresh geofences
          FloatingActionButton.small(
            heroTag: 'refreshGeo',
            onPressed: () async {
              try {
                final fences = await tl.Tracelet.getGeofences();
                setState(() => _geofences = fences);
              } catch (_) {}
            },
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _layerItem(
    String value,
    String label,
    IconData icon,
    bool on,
  ) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        leading: Icon(
          icon,
          size: 20,
          color: on ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(label),
        trailing: on
            ? Icon(
                Icons.check,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location marker with heading arrow
// ─────────────────────────────────────────────────────────────────────────────

class _LocationMarkerWidget extends StatelessWidget {
  const _LocationMarkerWidget({
    required this.isMoving,
    required this.heading,
    required this.speed,
  });

  final bool isMoving;
  final double heading;
  final double speed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (isMoving && speed > 0.5)
          Transform.rotate(
            angle: heading * math.pi / 180,
            child: const Align(
              alignment: Alignment.topCenter,
              child: Icon(Icons.navigation, size: 18, color: Colors.blue),
            ),
          ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isMoving ? Colors.blue : Colors.indigo,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: (isMoving ? Colors.blue : Colors.indigo).withAlpha(100),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trip pin
// ─────────────────────────────────────────────────────────────────────────────

class _TripPinWidget extends StatelessWidget {
  const _TripPinWidget({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(200),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trip info card
// ─────────────────────────────────────────────────────────────────────────────

class _TripInfoCard extends StatelessWidget {
  const _TripInfoCard({required this.trip});
  final tl.TripEvent trip;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(Icons.route, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${(trip.distance / 1000).toStringAsFixed(2)} km  |  '
                '${(trip.duration / 60).toStringAsFixed(1)} min  |  '
                '${(trip.averageSpeed * 3.6).toStringAsFixed(1)} km/h  |  '
                '${trip.waypoints.length} pts',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats item
// ─────────────────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).hintColor),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legend item
// ─────────────────────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 8)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail row for bottom sheets
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status chip for the overlay
// ─────────────────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.showToggle = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        if (showToggle) ...[
          const SizedBox(width: 2),
          Icon(Icons.touch_app, size: 9, color: color.withAlpha(120)),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map event for the event log
// ─────────────────────────────────────────────────────────────────────────────

class _MapEvent {
  const _MapEvent({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final DateTime time;
}
