import Foundation

/// Encodes a batch of location dictionaries into delta-compressed format.
///
/// The first location is emitted as a full reference (`ref: true`).
/// Subsequent locations are encoded as deltas relative to the previous.
///
/// Achieves 60–80% payload size reduction for high-frequency batch payloads.
public enum DeltaEncoder {

    /// Encode a batch of location maps into delta-compressed format.
    ///
    /// - Parameters:
    ///   - locations: Non-empty, timestamp-ordered location dictionaries.
    ///   - precision: Coordinate decimal places (5 ≈ 1.1 m, 6 ≈ 0.11 m).
    /// - Returns: Array of dictionaries ready for JSON serialization.
    public static func encode(_ locations: [[String: Any]],
                       precision: Int = 6) -> [[String: Any]] {
        guard !locations.isEmpty else { return [] }
        if locations.count == 1 {
            var ref = locations[0]
            ref["ref"] = true
            return [ref]
        }

        let factor = pow(10.0, Double(precision))
        var result = [[String: Any]]()

        // First location: full reference.
        var ref = locations[0]
        ref["ref"] = true
        result.append(ref)

        var prev = locations[0]
        for i in 1..<locations.count {
            let curr = locations[i]
            let delta = encodeDelta(prev: prev, curr: curr, factor: factor)
            result.append(["d": delta])
            prev = curr
        }

        return result
    }

    // MARK: - Private

    private static func encodeDelta(prev: [String: Any],
                                    curr: [String: Any],
                                    factor: Double) -> [String: Any] {
        var delta = [String: Any]()

        // UUID — always full.
        delta["u"] = curr["uuid"]

        // Δ timestamp (seconds).
        if let prevTs = parseTimestamp(prev["timestamp"]),
           let currTs = parseTimestamp(curr["timestamp"]) {
            delta["t"] = Int(currTs.timeIntervalSince(prevTs))
        }

        // Coordinates.
        if let prevCoords = prev["coords"] as? [String: Any],
           let currCoords = curr["coords"] as? [String: Any] {
            let prevLat = toDouble(prevCoords["latitude"])
            let currLat = toDouble(currCoords["latitude"])
            delta["la"] = Int(((currLat - prevLat) * factor).rounded())

            let prevLng = toDouble(prevCoords["longitude"])
            let currLng = toDouble(currCoords["longitude"])
            delta["lo"] = Int(((currLng - prevLng) * factor).rounded())

            delta["s"] = round(toDouble(currCoords["speed"]) - toDouble(prevCoords["speed"]), places: 2)
            delta["h"] = round(
                shortestArc(from: toDouble(prevCoords["heading"]),
                            to: toDouble(currCoords["heading"])),
                places: 2
            )
            delta["a"] = round(toDouble(currCoords["accuracy"]) - toDouble(prevCoords["accuracy"]), places: 2)
            delta["al"] = round(toDouble(currCoords["altitude"]) - toDouble(prevCoords["altitude"]), places: 2)
        }

        // Battery delta.
        if let prevBat = prev["battery"] as? [String: Any],
           let currBat = curr["battery"] as? [String: Any] {
            delta["b"] = round(toDouble(currBat["level"]) - toDouble(prevBat["level"]), places: 4)
        }

        return delta
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        // Retry without fractional seconds.
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }

    private static func toDouble(_ value: Any?) -> Double {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as Float: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return 0.0
        }
    }

    private static func round(_ value: Double, places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (value * f).rounded() / f
    }

    /// Shortest arc between two headings (0–360°). Returns value in [−180, 180].
    private static func shortestArc(from: Double, to: Double) -> Double {
        var diff = to - from
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }
}
