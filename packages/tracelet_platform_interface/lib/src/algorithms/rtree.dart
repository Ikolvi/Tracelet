import 'dart:math' as math;

import 'geo_utils.dart';

/// Axis-aligned bounding box for R-tree nodes.
class RTreeBBox {
  double minLat;
  double minLng;
  double maxLat;
  double maxLng;

  RTreeBBox(this.minLat, this.minLng, this.maxLat, this.maxLng);

  /// Create a bbox that contains a single point.
  factory RTreeBBox.fromPoint(double lat, double lng) =>
      RTreeBBox(lat, lng, lat, lng);

  /// Expand this bbox to contain [other].
  void expand(RTreeBBox other) {
    if (other.minLat < minLat) minLat = other.minLat;
    if (other.minLng < minLng) minLng = other.minLng;
    if (other.maxLat > maxLat) maxLat = other.maxLat;
    if (other.maxLng > maxLng) maxLng = other.maxLng;
  }

  /// Whether this bbox intersects [other].
  bool intersects(RTreeBBox other) {
    return minLat <= other.maxLat &&
        maxLat >= other.minLat &&
        minLng <= other.maxLng &&
        maxLng >= other.minLng;
  }

  /// Area of the bbox (in degree² — only used for ordering, not real area).
  double get area => (maxLat - minLat) * (maxLng - minLng);

  /// Area increase needed to encompass [other].
  double enlargement(RTreeBBox other) {
    final newMinLat = math.min(minLat, other.minLat);
    final newMinLng = math.min(minLng, other.minLng);
    final newMaxLat = math.max(maxLat, other.maxLat);
    final newMaxLng = math.max(maxLng, other.maxLng);
    return (newMaxLat - newMinLat) * (newMaxLng - newMinLng) - area;
  }

  @override
  String toString() => 'RTreeBBox($minLat,$minLng → $maxLat,$maxLng)';
}

/// A data entry stored in the R-tree leaf.
class _RTreeEntry<T> {
  _RTreeEntry(this.lat, this.lng, this.radius, this.data);

  final double lat;
  final double lng;
  final double radius;
  final T data;

  late final RTreeBBox bbox = _computeBBox();

  RTreeBBox _computeBBox() {
    // Convert radius (meters) to approximate lat/lng offset.
    final latOffset = radius / 111320.0;
    final lngOffset = radius / (111320.0 * math.cos(lat * math.pi / 180.0));
    return RTreeBBox(
      lat - latOffset,
      lng - lngOffset,
      lat + latOffset,
      lng + lngOffset,
    );
  }
}

/// Internal R-tree node.
class _RTreeNode<T> {
  _RTreeNode({required this.isLeaf});

  final bool isLeaf;
  final List<_RTreeNode<T>> children = [];
  final List<_RTreeEntry<T>> entries = [];
  late RTreeBBox bbox = RTreeBBox(
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );

  void recalculateBBox() {
    bbox = RTreeBBox(
      double.infinity,
      double.infinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );
    if (isLeaf) {
      for (final e in entries) {
        bbox.expand(e.bbox);
      }
    } else {
      for (final c in children) {
        bbox.expand(c.bbox);
      }
    }
  }

  int get count => isLeaf ? entries.length : children.length;
}

/// R-tree spatial index for efficient geofence proximity queries.
///
/// Supports O(log n) circle and bounding-box queries, enabling 10,000+
/// geofences with sub-millisecond lookup times.
///
/// Uses a classic R-tree with configurable branching factor [maxEntries].
/// On each location update, call [queryCircle] to find geofences within
/// the proximity radius instead of iterating all geofences.
///
/// ```dart
/// final tree = RTree<String>(maxEntries: 8);
/// tree.insert(37.7749, -122.4194, 200, 'home');
/// tree.insert(40.7128, -74.0060, 500, 'office');
///
/// final nearby = tree.queryCircle(37.7750, -122.4190, 1000);
/// print(nearby); // ['home']
/// ```
class RTree<T> {
  /// Creates a new R-tree.
  ///
  /// [maxEntries] controls the branching factor (default: 8).
  /// Higher values = shallower tree, wider nodes.
  RTree({this.maxEntries = 8}) : _minEntries = (maxEntries * 0.4).ceil();

  /// Maximum entries per node before splitting.
  final int maxEntries;

  /// Minimum entries per node (40% of max).
  // ignore: unused_field
  final int _minEntries;

  _RTreeNode<T>? _root;
  int _size = 0;

  /// Number of entries in the tree.
  int get size => _size;

  /// Whether the tree is empty.
  bool get isEmpty => _size == 0;

  /// Insert a geofence into the tree.
  ///
  /// [lat], [lng] is the center point, [radius] is in meters, [data] is
  /// the associated geofence object.
  void insert(double lat, double lng, double radius, T data) {
    final entry = _RTreeEntry<T>(lat, lng, radius, data);

    if (_root == null) {
      _root = _RTreeNode<T>(isLeaf: true);
      _root!.entries.add(entry);
      _root!.recalculateBBox();
      _size++;
      return;
    }

    // Track the path from root to the chosen leaf.
    final path = <_RTreeNode<T>>[];
    final leaf = _chooseLeaf(_root!, entry.bbox, path);
    leaf.entries.add(entry);
    leaf.recalculateBBox();
    _size++;

    if (leaf.entries.length > maxEntries) {
      _splitLeafAndPropagate(leaf, path);
    } else {
      // Propagate bbox changes up the path.
      for (final node in path) {
        node.recalculateBBox();
      }
    }
  }

  /// Remove the first entry matching [data] (by identity/equality).
  ///
  /// Returns `true` if the entry was found and removed.
  bool remove(T data) {
    if (_root == null) return false;
    final removed = _removeEntry(_root!, data);
    if (removed) {
      _size--;
      if (_size == 0) {
        _root = null;
      } else if (!_root!.isLeaf && _root!.children.length == 1) {
        _root = _root!.children.first;
      }
    }
    return removed;
  }

  /// Find all entries within [radiusMeters] of ([lat], [lng]).
  ///
  /// Uses the bounding box of the search circle for R-tree traversal,
  /// then applies exact haversine distance as a post-filter.
  List<T> queryCircle(double lat, double lng, double radiusMeters) {
    if (_root == null) return const [];

    // Approximate bbox for the search circle.
    final latOffset = radiusMeters / 111320.0;
    final lngOffset =
        radiusMeters / (111320.0 * math.cos(lat * math.pi / 180.0));
    final searchBBox = RTreeBBox(
      lat - latOffset,
      lng - lngOffset,
      lat + latOffset,
      lng + lngOffset,
    );

    final candidates = <T>[];
    _queryBBoxRecursive(_root!, searchBBox, (entry) {
      // Exact distance check.
      final dist = GeoUtils.haversine(lat, lng, entry.lat, entry.lng);
      if (dist <= radiusMeters + entry.radius) {
        candidates.add(entry.data);
      }
    });

    return candidates;
  }

  /// Find all entries whose bounding boxes intersect the given bbox.
  List<T> queryBBox(
    double minLat,
    double minLng,
    double maxLat,
    double maxLng,
  ) {
    if (_root == null) return const [];

    final searchBBox = RTreeBBox(minLat, minLng, maxLat, maxLng);
    final results = <T>[];
    _queryBBoxRecursive(_root!, searchBBox, (entry) {
      results.add(entry.data);
    });
    return results;
  }

  /// Clear all entries.
  void clear() {
    _root = null;
    _size = 0;
  }

  // ── Internal methods ────────────────────────────────────────────────────

  _RTreeNode<T> _chooseLeaf(
    _RTreeNode<T> node,
    RTreeBBox bbox,
    List<_RTreeNode<T>> path,
  ) {
    if (node.isLeaf) return node;

    path.add(node);

    // Choose the child that requires the least enlargement.
    _RTreeNode<T>? best;
    double bestEnlargement = double.infinity;
    double bestArea = double.infinity;

    for (final child in node.children) {
      final enlargement = child.bbox.enlargement(bbox);
      final area = child.bbox.area;
      if (enlargement < bestEnlargement ||
          (enlargement == bestEnlargement && area < bestArea)) {
        best = child;
        bestEnlargement = enlargement;
        bestArea = area;
      }
    }

    return _chooseLeaf(best!, bbox, path);
  }

  /// Split a leaf node and propagate splits upward through [path].
  void _splitLeafAndPropagate(_RTreeNode<T> leaf, List<_RTreeNode<T>> path) {
    final entries = List<_RTreeEntry<T>>.from(leaf.entries);
    leaf.entries.clear();

    final sibling = _RTreeNode<T>(isLeaf: true);

    _pickSeedsAndDistribute(entries, leaf, sibling);

    leaf.recalculateBBox();
    sibling.recalculateBBox();

    _insertSiblingIntoParent(leaf, sibling, path);
  }

  /// Pick seeds using quadratic split, then distribute entries between
  /// [node] and [sibling].
  void _pickSeedsAndDistribute(
    List<_RTreeEntry<T>> entries,
    _RTreeNode<T> node,
    _RTreeNode<T> sibling,
  ) {
    int seed1 = 0, seed2 = 1;
    double maxWaste = double.negativeInfinity;
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final combined = RTreeBBox(
          math.min(entries[i].bbox.minLat, entries[j].bbox.minLat),
          math.min(entries[i].bbox.minLng, entries[j].bbox.minLng),
          math.max(entries[i].bbox.maxLat, entries[j].bbox.maxLat),
          math.max(entries[i].bbox.maxLng, entries[j].bbox.maxLng),
        );
        final waste =
            combined.area - entries[i].bbox.area - entries[j].bbox.area;
        if (waste > maxWaste) {
          maxWaste = waste;
          seed1 = i;
          seed2 = j;
        }
      }
    }

    node.entries.add(entries[seed1]);
    sibling.entries.add(entries[seed2]);

    for (var i = 0; i < entries.length; i++) {
      if (i == seed1 || i == seed2) continue;
      node.recalculateBBox();
      sibling.recalculateBBox();
      final e1 = node.bbox.enlargement(entries[i].bbox);
      final e2 = sibling.bbox.enlargement(entries[i].bbox);
      if (e1 <= e2) {
        node.entries.add(entries[i]);
      } else {
        sibling.entries.add(entries[i]);
      }
    }
  }

  /// Insert [sibling] into the parent of [node], splitting the parent if
  /// it overflows. Walks up [path] toward the root.
  void _insertSiblingIntoParent(
    _RTreeNode<T> node,
    _RTreeNode<T> sibling,
    List<_RTreeNode<T>> path,
  ) {
    if (path.isEmpty) {
      // node is the root — create a new root.
      final newRoot = _RTreeNode<T>(isLeaf: false);
      newRoot.children.add(node);
      newRoot.children.add(sibling);
      newRoot.recalculateBBox();
      _root = newRoot;
      return;
    }

    final parent = path.removeLast();
    parent.children.add(sibling);
    parent.recalculateBBox();

    if (parent.children.length > maxEntries) {
      _splitInternalAndPropagate(parent, path);
    } else {
      // Propagate bbox changes up the remaining path.
      for (final ancestor in path) {
        ancestor.recalculateBBox();
      }
    }
  }

  /// Split an internal (non-leaf) node and propagate upward.
  void _splitInternalAndPropagate(
    _RTreeNode<T> node,
    List<_RTreeNode<T>> path,
  ) {
    final children = List<_RTreeNode<T>>.from(node.children);
    node.children.clear();

    final sibling = _RTreeNode<T>(isLeaf: false);

    // Pick seeds: two children with maximum wasted area.
    int seed1 = 0, seed2 = 1;
    double maxWaste = double.negativeInfinity;
    for (var i = 0; i < children.length; i++) {
      for (var j = i + 1; j < children.length; j++) {
        final combined = RTreeBBox(
          math.min(children[i].bbox.minLat, children[j].bbox.minLat),
          math.min(children[i].bbox.minLng, children[j].bbox.minLng),
          math.max(children[i].bbox.maxLat, children[j].bbox.maxLat),
          math.max(children[i].bbox.maxLng, children[j].bbox.maxLng),
        );
        final waste =
            combined.area - children[i].bbox.area - children[j].bbox.area;
        if (waste > maxWaste) {
          maxWaste = waste;
          seed1 = i;
          seed2 = j;
        }
      }
    }

    node.children.add(children[seed1]);
    sibling.children.add(children[seed2]);

    for (var i = 0; i < children.length; i++) {
      if (i == seed1 || i == seed2) continue;
      node.recalculateBBox();
      sibling.recalculateBBox();
      final e1 = node.bbox.enlargement(children[i].bbox);
      final e2 = sibling.bbox.enlargement(children[i].bbox);
      if (e1 <= e2) {
        node.children.add(children[i]);
      } else {
        sibling.children.add(children[i]);
      }
    }

    node.recalculateBBox();
    sibling.recalculateBBox();

    _insertSiblingIntoParent(node, sibling, path);
  }

  void _queryBBoxRecursive(
    _RTreeNode<T> node,
    RTreeBBox searchBBox,
    void Function(_RTreeEntry<T>) callback,
  ) {
    if (!node.bbox.intersects(searchBBox)) return;

    if (node.isLeaf) {
      for (final entry in node.entries) {
        if (entry.bbox.intersects(searchBBox)) {
          callback(entry);
        }
      }
    } else {
      for (final child in node.children) {
        _queryBBoxRecursive(child, searchBBox, callback);
      }
    }
  }

  bool _removeEntry(_RTreeNode<T> node, T data) {
    if (node.isLeaf) {
      final idx = node.entries.indexWhere((e) => e.data == data);
      if (idx >= 0) {
        node.entries.removeAt(idx);
        node.recalculateBBox();
        return true;
      }
      return false;
    }

    for (final child in node.children) {
      if (_removeEntry(child, data)) {
        if (child.count == 0) {
          node.children.remove(child);
        }
        node.recalculateBBox();
        return true;
      }
    }
    return false;
  }
}
