package com.ikolvi.tracelet.sdk.algorithm

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min

/**
 * Axis-aligned bounding box for R-tree nodes.
 */
internal class RTreeBBox(
    var minLat: Double,
    var minLng: Double,
    var maxLat: Double,
    var maxLng: Double,
) {
    companion object {
        fun fromPoint(lat: Double, lng: Double) = RTreeBBox(lat, lng, lat, lng)
    }

    /** Expand this bbox to contain [other]. */
    fun expand(other: RTreeBBox) {
        if (other.minLat < minLat) minLat = other.minLat
        if (other.minLng < minLng) minLng = other.minLng
        if (other.maxLat > maxLat) maxLat = other.maxLat
        if (other.maxLng > maxLng) maxLng = other.maxLng
    }

    /** Whether this bbox intersects [other]. */
    fun intersects(other: RTreeBBox): Boolean {
        return minLat <= other.maxLat &&
                maxLat >= other.minLat &&
                minLng <= other.maxLng &&
                maxLng >= other.minLng
    }

    /** Area of the bbox (degree² — only used for ordering, not real area). */
    val area: Double get() = (maxLat - minLat) * (maxLng - minLng)

    /** Area increase needed to encompass [other]. */
    fun enlargement(other: RTreeBBox): Double {
        val newMinLat = min(minLat, other.minLat)
        val newMinLng = min(minLng, other.minLng)
        val newMaxLat = max(maxLat, other.maxLat)
        val newMaxLng = max(maxLng, other.maxLng)
        return (newMaxLat - newMinLat) * (newMaxLng - newMinLng) - area
    }
}

/**
 * A data entry stored in the R-tree leaf.
 */
internal class RTreeEntry<T>(
    val lat: Double,
    val lng: Double,
    val radius: Double,
    val data: T,
) {
    val bbox: RTreeBBox by lazy {
        val latOffset = radius / 111320.0
        val lngOffset = radius / (111320.0 * cos(lat * PI / 180.0))
        RTreeBBox(
            lat - latOffset,
            lng - lngOffset,
            lat + latOffset,
            lng + lngOffset,
        )
    }
}

/**
 * Internal R-tree node.
 */
internal class RTreeNode<T>(val isLeaf: Boolean) {
    val children = mutableListOf<RTreeNode<T>>()
    val entries = mutableListOf<RTreeEntry<T>>()
    var bbox = RTreeBBox(
        Double.MAX_VALUE,
        Double.MAX_VALUE,
        -Double.MAX_VALUE,
        -Double.MAX_VALUE,
    )

    fun recalculateBBox() {
        bbox = RTreeBBox(
            Double.MAX_VALUE,
            Double.MAX_VALUE,
            -Double.MAX_VALUE,
            -Double.MAX_VALUE,
        )
        if (isLeaf) {
            for (e in entries) bbox.expand(e.bbox)
        } else {
            for (c in children) bbox.expand(c.bbox)
        }
    }

    val count: Int get() = if (isLeaf) entries.size else children.size
}

/**
 * R-tree spatial index for efficient geofence proximity queries.
 *
 * Supports O(log n) circle and bounding-box queries, enabling 10,000+
 * geofences with sub-millisecond lookup times.
 *
 * Uses a classic R-tree with configurable branching factor [maxEntries].
 * On each location update, call [queryCircle] to find geofences within
 * the proximity radius instead of iterating all geofences.
 */
class RTree<T>(val maxEntries: Int = 8) {
    private val minEntries = (maxEntries * 0.4).toInt().coerceAtLeast(1)

    private var root: RTreeNode<T>? = null
    private var _size = 0

    /** Number of entries in the tree. */
    val size: Int get() = _size

    /** Whether the tree is empty. */
    val isEmpty: Boolean get() = _size == 0

    /**
     * Insert a geofence into the tree.
     *
     * [lat], [lng] is the center point, [radius] is in meters, [data] is
     * the associated geofence object.
     */
    fun insert(lat: Double, lng: Double, radius: Double, data: T) {
        val entry = RTreeEntry(lat, lng, radius, data)

        if (root == null) {
            root = RTreeNode(isLeaf = true)
            root!!.entries.add(entry)
            root!!.recalculateBBox()
            _size++
            return
        }

        val path = mutableListOf<RTreeNode<T>>()
        val leaf = chooseLeaf(root!!, entry.bbox, path)
        leaf.entries.add(entry)
        leaf.recalculateBBox()
        _size++

        if (leaf.entries.size > maxEntries) {
            splitLeafAndPropagate(leaf, path)
        } else {
            for (node in path) node.recalculateBBox()
        }
    }

    /**
     * Remove the first entry matching [data] (by equality).
     * Returns true if found and removed.
     */
    fun remove(data: T): Boolean {
        if (root == null) return false
        val removed = removeEntry(root!!, data)
        if (removed) {
            _size--
            if (_size == 0) {
                root = null
            } else if (!root!!.isLeaf && root!!.children.size == 1) {
                root = root!!.children.first()
            }
        }
        return removed
    }

    /**
     * Find all entries within [radiusMeters] of ([lat], [lng]).
     *
     * Uses the bounding box of the search circle for R-tree traversal,
     * then applies exact haversine distance as a post-filter.
     */
    fun queryCircle(lat: Double, lng: Double, radiusMeters: Double): List<T> {
        if (root == null) return emptyList()

        val latOffset = radiusMeters / 111320.0
        val lngOffset = radiusMeters / (111320.0 * cos(lat * PI / 180.0))
        val searchBBox = RTreeBBox(
            lat - latOffset,
            lng - lngOffset,
            lat + latOffset,
            lng + lngOffset,
        )

        val candidates = mutableListOf<T>()
        queryBBoxRecursive(root!!, searchBBox) { entry ->
            val dist = GeoUtils.haversine(lat, lng, entry.lat, entry.lng)
            if (dist <= radiusMeters + entry.radius) {
                candidates.add(entry.data)
            }
        }
        return candidates
    }

    /**
     * Find all entries whose bounding boxes intersect the given bbox.
     */
    fun queryBBox(
        minLat: Double,
        minLng: Double,
        maxLat: Double,
        maxLng: Double,
    ): List<T> {
        if (root == null) return emptyList()

        val searchBBox = RTreeBBox(minLat, minLng, maxLat, maxLng)
        val results = mutableListOf<T>()
        queryBBoxRecursive(root!!, searchBBox) { entry ->
            results.add(entry.data)
        }
        return results
    }

    /** Clear all entries. */
    fun clear() {
        root = null
        _size = 0
    }

    // ── Internal methods ────────────────────────────────────────────────────

    private fun chooseLeaf(
        node: RTreeNode<T>,
        bbox: RTreeBBox,
        path: MutableList<RTreeNode<T>>,
    ): RTreeNode<T> {
        if (node.isLeaf) return node

        path.add(node)

        var best: RTreeNode<T>? = null
        var bestEnlargement = Double.MAX_VALUE
        var bestArea = Double.MAX_VALUE

        for (child in node.children) {
            val enlargement = child.bbox.enlargement(bbox)
            val area = child.bbox.area
            if (enlargement < bestEnlargement ||
                (enlargement == bestEnlargement && area < bestArea)
            ) {
                best = child
                bestEnlargement = enlargement
                bestArea = area
            }
        }

        return chooseLeaf(best!!, bbox, path)
    }

    private fun splitLeafAndPropagate(leaf: RTreeNode<T>, path: MutableList<RTreeNode<T>>) {
        val entries = ArrayList(leaf.entries)
        leaf.entries.clear()

        val sibling = RTreeNode<T>(isLeaf = true)
        pickSeedsAndDistributeEntries(entries, leaf, sibling)

        leaf.recalculateBBox()
        sibling.recalculateBBox()

        insertSiblingIntoParent(leaf, sibling, path)
    }

    private fun pickSeedsAndDistributeEntries(
        entries: List<RTreeEntry<T>>,
        node: RTreeNode<T>,
        sibling: RTreeNode<T>,
    ) {
        var seed1 = 0
        var seed2 = 1
        var maxWaste = -Double.MAX_VALUE

        for (i in entries.indices) {
            for (j in i + 1 until entries.size) {
                val combined = RTreeBBox(
                    min(entries[i].bbox.minLat, entries[j].bbox.minLat),
                    min(entries[i].bbox.minLng, entries[j].bbox.minLng),
                    max(entries[i].bbox.maxLat, entries[j].bbox.maxLat),
                    max(entries[i].bbox.maxLng, entries[j].bbox.maxLng),
                )
                val waste = combined.area - entries[i].bbox.area - entries[j].bbox.area
                if (waste > maxWaste) {
                    maxWaste = waste
                    seed1 = i
                    seed2 = j
                }
            }
        }

        node.entries.add(entries[seed1])
        sibling.entries.add(entries[seed2])

        for (i in entries.indices) {
            if (i == seed1 || i == seed2) continue
            node.recalculateBBox()
            sibling.recalculateBBox()
            val e1 = node.bbox.enlargement(entries[i].bbox)
            val e2 = sibling.bbox.enlargement(entries[i].bbox)
            if (e1 <= e2) {
                node.entries.add(entries[i])
            } else {
                sibling.entries.add(entries[i])
            }
        }
    }

    private fun insertSiblingIntoParent(
        node: RTreeNode<T>,
        sibling: RTreeNode<T>,
        path: MutableList<RTreeNode<T>>,
    ) {
        if (path.isEmpty()) {
            val newRoot = RTreeNode<T>(isLeaf = false)
            newRoot.children.add(node)
            newRoot.children.add(sibling)
            newRoot.recalculateBBox()
            root = newRoot
            return
        }

        val parent = path.removeAt(path.size - 1)
        parent.children.add(sibling)
        parent.recalculateBBox()

        if (parent.children.size > maxEntries) {
            splitInternalAndPropagate(parent, path)
        } else {
            for (ancestor in path) ancestor.recalculateBBox()
        }
    }

    private fun splitInternalAndPropagate(
        node: RTreeNode<T>,
        path: MutableList<RTreeNode<T>>,
    ) {
        val children = ArrayList(node.children)
        node.children.clear()

        val sibling = RTreeNode<T>(isLeaf = false)

        var seed1 = 0
        var seed2 = 1
        var maxWaste = -Double.MAX_VALUE
        for (i in children.indices) {
            for (j in i + 1 until children.size) {
                val combined = RTreeBBox(
                    min(children[i].bbox.minLat, children[j].bbox.minLat),
                    min(children[i].bbox.minLng, children[j].bbox.minLng),
                    max(children[i].bbox.maxLat, children[j].bbox.maxLat),
                    max(children[i].bbox.maxLng, children[j].bbox.maxLng),
                )
                val waste = combined.area - children[i].bbox.area - children[j].bbox.area
                if (waste > maxWaste) {
                    maxWaste = waste
                    seed1 = i
                    seed2 = j
                }
            }
        }

        node.children.add(children[seed1])
        sibling.children.add(children[seed2])

        for (i in children.indices) {
            if (i == seed1 || i == seed2) continue
            node.recalculateBBox()
            sibling.recalculateBBox()
            val e1 = node.bbox.enlargement(children[i].bbox)
            val e2 = sibling.bbox.enlargement(children[i].bbox)
            if (e1 <= e2) {
                node.children.add(children[i])
            } else {
                sibling.children.add(children[i])
            }
        }

        node.recalculateBBox()
        sibling.recalculateBBox()

        insertSiblingIntoParent(node, sibling, path)
    }

    private fun queryBBoxRecursive(
        node: RTreeNode<T>,
        searchBBox: RTreeBBox,
        callback: (RTreeEntry<T>) -> Unit,
    ) {
        if (!node.bbox.intersects(searchBBox)) return

        if (node.isLeaf) {
            for (entry in node.entries) {
                if (entry.bbox.intersects(searchBBox)) {
                    callback(entry)
                }
            }
        } else {
            for (child in node.children) {
                queryBBoxRecursive(child, searchBBox, callback)
            }
        }
    }

    private fun removeEntry(node: RTreeNode<T>, data: T): Boolean {
        if (node.isLeaf) {
            val idx = node.entries.indexOfFirst { it.data == data }
            if (idx >= 0) {
                node.entries.removeAt(idx)
                node.recalculateBBox()
                return true
            }
            return false
        }

        for (child in node.children) {
            if (removeEntry(child, data)) {
                if (child.count == 0) {
                    node.children.remove(child)
                }
                node.recalculateBBox()
                return true
            }
        }
        return false
    }
}
