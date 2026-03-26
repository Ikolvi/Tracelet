import Foundation

/// Axis-aligned bounding box for R-tree nodes.
internal class RTreeBBox {
    var minLat: Double
    var minLng: Double
    var maxLat: Double
    var maxLng: Double

    init(_ minLat: Double, _ minLng: Double, _ maxLat: Double, _ maxLng: Double) {
        self.minLat = minLat
        self.minLng = minLng
        self.maxLat = maxLat
        self.maxLng = maxLng
    }

    static func fromPoint(_ lat: Double, _ lng: Double) -> RTreeBBox {
        RTreeBBox(lat, lng, lat, lng)
    }

    /// Expand this bbox to contain `other`.
    func expand(_ other: RTreeBBox) {
        if other.minLat < minLat { minLat = other.minLat }
        if other.minLng < minLng { minLng = other.minLng }
        if other.maxLat > maxLat { maxLat = other.maxLat }
        if other.maxLng > maxLng { maxLng = other.maxLng }
    }

    /// Whether this bbox intersects `other`.
    func intersects(_ other: RTreeBBox) -> Bool {
        minLat <= other.maxLat &&
        maxLat >= other.minLat &&
        minLng <= other.maxLng &&
        maxLng >= other.minLng
    }

    /// Area of the bbox (degree² — only used for ordering, not real area).
    var area: Double { (maxLat - minLat) * (maxLng - minLng) }

    /// Area increase needed to encompass `other`.
    func enlargement(_ other: RTreeBBox) -> Double {
        let newMinLat = min(minLat, other.minLat)
        let newMinLng = min(minLng, other.minLng)
        let newMaxLat = max(maxLat, other.maxLat)
        let newMaxLng = max(maxLng, other.maxLng)
        return (newMaxLat - newMinLat) * (newMaxLng - newMinLng) - area
    }
}

/// A data entry stored in the R-tree leaf.
internal class RTreeEntry<T> {
    let lat: Double
    let lng: Double
    let radius: Double
    let data: T

    lazy var bbox: RTreeBBox = {
        let latOffset = radius / 111320.0
        let lngOffset = radius / (111320.0 * cos(lat * .pi / 180.0))
        return RTreeBBox(
            lat - latOffset,
            lng - lngOffset,
            lat + latOffset,
            lng + lngOffset
        )
    }()

    init(lat: Double, lng: Double, radius: Double, data: T) {
        self.lat = lat
        self.lng = lng
        self.radius = radius
        self.data = data
    }
}

/// Internal R-tree node.
internal class RTreeNode<T> {
    let isLeaf: Bool
    var children: [RTreeNode<T>] = []
    var entries: [RTreeEntry<T>] = []
    var bbox = RTreeBBox(
        Double.greatestFiniteMagnitude,
        Double.greatestFiniteMagnitude,
        -Double.greatestFiniteMagnitude,
        -Double.greatestFiniteMagnitude
    )

    init(isLeaf: Bool) {
        self.isLeaf = isLeaf
    }

    func recalculateBBox() {
        bbox = RTreeBBox(
            Double.greatestFiniteMagnitude,
            Double.greatestFiniteMagnitude,
            -Double.greatestFiniteMagnitude,
            -Double.greatestFiniteMagnitude
        )
        if isLeaf {
            for e in entries { bbox.expand(e.bbox) }
        } else {
            for c in children { bbox.expand(c.bbox) }
        }
    }

    var count: Int { isLeaf ? entries.count : children.count }
}

/// R-tree spatial index for efficient geofence proximity queries.
///
/// Supports O(log n) circle and bounding-box queries, enabling 10,000+
/// geofences with sub-millisecond lookup times.
///
/// Uses a classic R-tree with configurable branching factor `maxEntries`.
/// On each location update, call `queryCircle` to find geofences within
/// the proximity radius instead of iterating all geofences.
public class RTree<T> {
    /// Maximum entries per node before splitting.
    public let maxEntries: Int

    /// Minimum entries per node (40% of max).
    private let minEntries: Int

    private var root: RTreeNode<T>?
    private var _size = 0

    /// Number of entries in the tree.
    public var size: Int { _size }

    /// Whether the tree is empty.
    public var isEmpty: Bool { _size == 0 }

    /// Creates a new R-tree.
    public init(maxEntries: Int = 8) {
        self.maxEntries = maxEntries
        self.minEntries = max(Int(Double(maxEntries) * 0.4), 1)
    }

    /// Insert a geofence into the tree.
    public func insert(lat: Double, lng: Double, radius: Double, data: T) {
        let entry = RTreeEntry(lat: lat, lng: lng, radius: radius, data: data)

        guard let root = root else {
            self.root = RTreeNode(isLeaf: true)
            self.root!.entries.append(entry)
            self.root!.recalculateBBox()
            _size += 1
            return
        }

        var path: [RTreeNode<T>] = []
        let leaf = chooseLeaf(root, entry.bbox, &path)
        leaf.entries.append(entry)
        leaf.recalculateBBox()
        _size += 1

        if leaf.entries.count > maxEntries {
            splitLeafAndPropagate(leaf, &path)
        } else {
            for node in path { node.recalculateBBox() }
        }
    }

    /// Remove the first entry matching `data` (by reference equality for classes, value equality for value types).
    public func remove(_ data: T) -> Bool where T: Equatable {
        guard let root = root else { return false }
        let removed = removeEntry(root, data)
        if removed {
            _size -= 1
            if _size == 0 {
                self.root = nil
            } else if !root.isLeaf && root.children.count == 1 {
                self.root = root.children.first
            }
        }
        return removed
    }

    /// Find all entries within `radiusMeters` of (`lat`, `lng`).
    public func queryCircle(lat: Double, lng: Double, radiusMeters: Double) -> [T] {
        guard let root = root else { return [] }

        let latOffset = radiusMeters / 111320.0
        let lngOffset = radiusMeters / (111320.0 * cos(lat * .pi / 180.0))
        let searchBBox = RTreeBBox(
            lat - latOffset,
            lng - lngOffset,
            lat + latOffset,
            lng + lngOffset
        )

        var candidates: [T] = []
        queryBBoxRecursive(root, searchBBox) { entry in
            let dist = GeoUtils.haversine(lat, lng, entry.lat, entry.lng)
            if dist <= radiusMeters + entry.radius {
                candidates.append(entry.data)
            }
        }
        return candidates
    }

    /// Find all entries whose bounding boxes intersect the given bbox.
    public func queryBBox(
        minLat: Double, minLng: Double,
        maxLat: Double, maxLng: Double
    ) -> [T] {
        guard let root = root else { return [] }

        let searchBBox = RTreeBBox(minLat, minLng, maxLat, maxLng)
        var results: [T] = []
        queryBBoxRecursive(root, searchBBox) { entry in
            results.append(entry.data)
        }
        return results
    }

    /// Clear all entries.
    public func clear() {
        root = nil
        _size = 0
    }

    // MARK: - Internal methods

    private func chooseLeaf(
        _ node: RTreeNode<T>,
        _ bbox: RTreeBBox,
        _ path: inout [RTreeNode<T>]
    ) -> RTreeNode<T> {
        if node.isLeaf { return node }

        path.append(node)

        var best: RTreeNode<T>?
        var bestEnlargement = Double.greatestFiniteMagnitude
        var bestArea = Double.greatestFiniteMagnitude

        for child in node.children {
            let enlargement = child.bbox.enlargement(bbox)
            let area = child.bbox.area
            if enlargement < bestEnlargement ||
               (enlargement == bestEnlargement && area < bestArea) {
                best = child
                bestEnlargement = enlargement
                bestArea = area
            }
        }

        return chooseLeaf(best!, bbox, &path)
    }

    private func splitLeafAndPropagate(
        _ leaf: RTreeNode<T>,
        _ path: inout [RTreeNode<T>]
    ) {
        let entries = Array(leaf.entries)
        leaf.entries.removeAll()

        let sibling = RTreeNode<T>(isLeaf: true)
        pickSeedsAndDistributeEntries(entries, leaf, sibling)

        leaf.recalculateBBox()
        sibling.recalculateBBox()

        insertSiblingIntoParent(leaf, sibling, &path)
    }

    private func pickSeedsAndDistributeEntries(
        _ entries: [RTreeEntry<T>],
        _ node: RTreeNode<T>,
        _ sibling: RTreeNode<T>
    ) {
        var seed1 = 0, seed2 = 1
        var maxWaste = -Double.greatestFiniteMagnitude

        for i in 0..<entries.count {
            for j in (i + 1)..<entries.count {
                let combined = RTreeBBox(
                    min(entries[i].bbox.minLat, entries[j].bbox.minLat),
                    min(entries[i].bbox.minLng, entries[j].bbox.minLng),
                    max(entries[i].bbox.maxLat, entries[j].bbox.maxLat),
                    max(entries[i].bbox.maxLng, entries[j].bbox.maxLng)
                )
                let waste = combined.area - entries[i].bbox.area - entries[j].bbox.area
                if waste > maxWaste {
                    maxWaste = waste
                    seed1 = i
                    seed2 = j
                }
            }
        }

        node.entries.append(entries[seed1])
        sibling.entries.append(entries[seed2])

        for i in 0..<entries.count {
            if i == seed1 || i == seed2 { continue }
            node.recalculateBBox()
            sibling.recalculateBBox()
            let e1 = node.bbox.enlargement(entries[i].bbox)
            let e2 = sibling.bbox.enlargement(entries[i].bbox)
            if e1 <= e2 {
                node.entries.append(entries[i])
            } else {
                sibling.entries.append(entries[i])
            }
        }
    }

    private func insertSiblingIntoParent(
        _ node: RTreeNode<T>,
        _ sibling: RTreeNode<T>,
        _ path: inout [RTreeNode<T>]
    ) {
        if path.isEmpty {
            let newRoot = RTreeNode<T>(isLeaf: false)
            newRoot.children.append(node)
            newRoot.children.append(sibling)
            newRoot.recalculateBBox()
            root = newRoot
            return
        }

        let parent = path.removeLast()
        parent.children.append(sibling)
        parent.recalculateBBox()

        if parent.children.count > maxEntries {
            splitInternalAndPropagate(parent, &path)
        } else {
            for ancestor in path { ancestor.recalculateBBox() }
        }
    }

    private func splitInternalAndPropagate(
        _ node: RTreeNode<T>,
        _ path: inout [RTreeNode<T>]
    ) {
        let children = Array(node.children)
        node.children.removeAll()

        let sibling = RTreeNode<T>(isLeaf: false)

        var seed1 = 0, seed2 = 1
        var maxWaste = -Double.greatestFiniteMagnitude
        for i in 0..<children.count {
            for j in (i + 1)..<children.count {
                let combined = RTreeBBox(
                    min(children[i].bbox.minLat, children[j].bbox.minLat),
                    min(children[i].bbox.minLng, children[j].bbox.minLng),
                    max(children[i].bbox.maxLat, children[j].bbox.maxLat),
                    max(children[i].bbox.maxLng, children[j].bbox.maxLng)
                )
                let waste = combined.area - children[i].bbox.area - children[j].bbox.area
                if waste > maxWaste {
                    maxWaste = waste
                    seed1 = i
                    seed2 = j
                }
            }
        }

        node.children.append(children[seed1])
        sibling.children.append(children[seed2])

        for i in 0..<children.count {
            if i == seed1 || i == seed2 { continue }
            node.recalculateBBox()
            sibling.recalculateBBox()
            let e1 = node.bbox.enlargement(children[i].bbox)
            let e2 = sibling.bbox.enlargement(children[i].bbox)
            if e1 <= e2 {
                node.children.append(children[i])
            } else {
                sibling.children.append(children[i])
            }
        }

        node.recalculateBBox()
        sibling.recalculateBBox()

        insertSiblingIntoParent(node, sibling, &path)
    }

    private func queryBBoxRecursive(
        _ node: RTreeNode<T>,
        _ searchBBox: RTreeBBox,
        _ callback: (RTreeEntry<T>) -> Void
    ) {
        guard node.bbox.intersects(searchBBox) else { return }

        if node.isLeaf {
            for entry in node.entries {
                if entry.bbox.intersects(searchBBox) {
                    callback(entry)
                }
            }
        } else {
            for child in node.children {
                queryBBoxRecursive(child, searchBBox, callback)
            }
        }
    }

    private func removeEntry(_ node: RTreeNode<T>, _ data: T) -> Bool where T: Equatable {
        if node.isLeaf {
            if let idx = node.entries.firstIndex(where: { $0.data == data }) {
                node.entries.remove(at: idx)
                node.recalculateBBox()
                return true
            }
            return false
        }

        for (i, child) in node.children.enumerated() {
            if removeEntry(child, data) {
                if child.count == 0 {
                    node.children.remove(at: i)
                }
                node.recalculateBBox()
                return true
            }
        }
        return false
    }
}
