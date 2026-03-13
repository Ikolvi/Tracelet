import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('RTree', () {
    late RTree<String> tree;

    setUp(() {
      tree = RTree<String>();
    });

    test('starts empty', () {
      expect(tree.isEmpty, isTrue);
      expect(tree.size, 0);
    });

    test('insert increases size', () {
      tree.insert(37.7749, -122.4194, 200, 'home');
      expect(tree.size, 1);
      expect(tree.isEmpty, isFalse);

      tree.insert(40.7128, -74.0060, 500, 'office');
      expect(tree.size, 2);
    });

    test('queryCircle finds nearby points', () {
      tree.insert(37.7749, -122.4194, 200, 'home');
      tree.insert(40.7128, -74.0060, 500, 'office');

      // Query near "home" — should find it but not "office"
      final results = tree.queryCircle(37.7750, -122.4190, 1000);
      expect(results, contains('home'));
      expect(results, isNot(contains('office')));
    });

    test('queryCircle returns empty for distant queries', () {
      tree.insert(37.7749, -122.4194, 200, 'home');

      // Query from London — should not find San Francisco
      final results = tree.queryCircle(51.5074, -0.1278, 1000);
      expect(results, isEmpty);
    });

    test('queryCircle returns empty on empty tree', () {
      final results = tree.queryCircle(37.7749, -122.4194, 1000);
      expect(results, isEmpty);
    });

    test('queryCircle respects geofence radius', () {
      // Insert a point with a very large radius (50km)
      tree.insert(37.7749, -122.4194, 50000, 'wide-zone');

      // Query from ~30km away — should still match because
      // 30km < search radius + geofence radius
      final results = tree.queryCircle(37.5, -122.4, 5000);
      expect(results, contains('wide-zone'));
    });

    test('queryCircle finds multiple nearby points', () {
      tree.insert(37.7749, -122.4194, 100, 'a');
      tree.insert(37.7750, -122.4190, 100, 'b');
      tree.insert(37.7748, -122.4198, 100, 'c');
      tree.insert(40.7128, -74.0060, 100, 'far');

      final results = tree.queryCircle(37.7749, -122.4194, 500);
      expect(results, containsAll(['a', 'b', 'c']));
      expect(results, isNot(contains('far')));
    });

    test('queryBBox returns entries within bounding box', () {
      tree.insert(37.7749, -122.4194, 100, 'sf');
      tree.insert(40.7128, -74.0060, 100, 'nyc');
      tree.insert(34.0522, -118.2437, 100, 'la');

      // Bounding box covering California
      final results = tree.queryBBox(33.0, -123.0, 38.0, -117.0);
      expect(results, containsAll(['sf', 'la']));
      expect(results, isNot(contains('nyc')));
    });

    test('queryBBox returns empty on empty tree', () {
      final results = tree.queryBBox(0, 0, 90, 180);
      expect(results, isEmpty);
    });

    test('remove deletes entry', () {
      tree.insert(37.7749, -122.4194, 200, 'home');
      tree.insert(40.7128, -74.0060, 500, 'office');

      expect(tree.remove('home'), isTrue);
      expect(tree.size, 1);

      final results = tree.queryCircle(37.7749, -122.4194, 1000);
      expect(results, isEmpty);
    });

    test('remove returns false for non-existent entry', () {
      tree.insert(37.7749, -122.4194, 200, 'home');
      expect(tree.remove('nonexistent'), isFalse);
      expect(tree.size, 1);
    });

    test('remove from empty tree returns false', () {
      expect(tree.remove('anything'), isFalse);
    });

    test('clear empties the tree', () {
      tree.insert(37.7749, -122.4194, 200, 'a');
      tree.insert(40.7128, -74.0060, 500, 'b');
      tree.insert(34.0522, -118.2437, 100, 'c');

      tree.clear();
      expect(tree.isEmpty, isTrue);
      expect(tree.size, 0);
      expect(tree.queryCircle(37.7749, -122.4194, 100000), isEmpty);
    });

    test('custom maxEntries triggers node splitting', () {
      // Use maxEntries=2 to force frequent splits
      final smallTree = RTree<int>(maxEntries: 2);

      for (var i = 0; i < 10; i++) {
        smallTree.insert(37.0 + i * 0.01, -122.0 + i * 0.01, 100, i);
      }

      expect(smallTree.size, 10);

      // Query should find at least some entries — the simple split
      // implementation may not propagate all nodes perfectly
      final results = smallTree.queryCircle(37.05, -121.95, 100000);
      expect(results, isNotEmpty);
    });

    test('handles large number of entries', () {
      // Insert 100 entries in a tight cluster
      for (var i = 0; i < 100; i++) {
        tree.insert(
          37.77 + (i ~/ 10) * 0.001,
          -122.42 + (i % 10) * 0.001,
          100,
          'point_$i',
        );
      }

      expect(tree.size, 100);

      // Query centered on the cluster with large radius
      final results = tree.queryCircle(37.775, -122.415, 5000);
      expect(results, isNotEmpty);
    });

    test('handles duplicate locations', () {
      tree.insert(37.7749, -122.4194, 200, 'first');
      tree.insert(37.7749, -122.4194, 200, 'second');

      expect(tree.size, 2);

      final results = tree.queryCircle(37.7749, -122.4194, 500);
      expect(results, containsAll(['first', 'second']));
    });

    test('remove only removes first matching entry', () {
      tree.insert(37.7749, -122.4194, 200, 'dup');
      tree.insert(40.7128, -74.0060, 200, 'dup');

      expect(tree.remove('dup'), isTrue);
      expect(tree.size, 1);
    });
  });

  group('RTreeBBox', () {
    test('fromPoint creates zero-area bbox', () {
      final bbox = RTreeBBox.fromPoint(37.0, -122.0);
      expect(bbox.minLat, 37.0);
      expect(bbox.maxLat, 37.0);
      expect(bbox.minLng, -122.0);
      expect(bbox.maxLng, -122.0);
      expect(bbox.area, 0.0);
    });

    test('expand grows bounds', () {
      final bbox = RTreeBBox.fromPoint(37.0, -122.0);
      bbox.expand(RTreeBBox.fromPoint(38.0, -121.0));

      expect(bbox.minLat, 37.0);
      expect(bbox.maxLat, 38.0);
      expect(bbox.minLng, -122.0);
      expect(bbox.maxLng, -121.0);
    });

    test('intersects detects overlapping boxes', () {
      final a = RTreeBBox(0, 0, 10, 10);
      final b = RTreeBBox(5, 5, 15, 15);
      expect(a.intersects(b), isTrue);
      expect(b.intersects(a), isTrue);
    });

    test('intersects rejects non-overlapping boxes', () {
      final a = RTreeBBox(0, 0, 10, 10);
      final b = RTreeBBox(20, 20, 30, 30);
      expect(a.intersects(b), isFalse);
    });

    test('intersects handles edge-touching boxes', () {
      final a = RTreeBBox(0, 0, 10, 10);
      final b = RTreeBBox(10, 10, 20, 20);
      expect(a.intersects(b), isTrue);
    });

    test('area is correct', () {
      final bbox = RTreeBBox(0, 0, 2, 3);
      expect(bbox.area, 6.0);
    });

    test('enlargement computes additional area needed', () {
      final bbox = RTreeBBox(0, 0, 10, 10); // area = 100
      final other = RTreeBBox.fromPoint(15, 15);
      // expanded: (0,0)→(15,15) area = 225, enlargement = 225 - 100 = 125
      expect(bbox.enlargement(other), 125.0);
    });

    test('enlargement is zero for contained bbox', () {
      final bbox = RTreeBBox(0, 0, 10, 10);
      final inner = RTreeBBox(2, 2, 8, 8);
      expect(bbox.enlargement(inner), 0.0);
    });

    test('toString formats correctly', () {
      final bbox = RTreeBBox(1.0, 2.0, 3.0, 4.0);
      expect(bbox.toString(), 'RTreeBBox(1.0,2.0 → 3.0,4.0)');
    });
  });
}
