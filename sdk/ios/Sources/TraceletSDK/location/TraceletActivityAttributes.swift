import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The attributes required to launch the Tracelet Live Activity.
/// Developers must use these attributes in their Xcode Widget Extension.
@available(iOS 16.1, *)
public struct TraceletActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// A dynamic status string (e.g., "Tracking active", "Paused")
        public var status: String

        /// When non-nil and `showTimer` is true, the widget renders a
        /// self-ticking count-up clock from this instant — the OS ticks it,
        /// no updates are pushed.
        public var startedAt: Date?

        /// Whether to render the self-ticking count-up clock.
        public var showTimer: Bool

        public init(status: String, startedAt: Date? = nil, showTimer: Bool = false) {
            self.status = status
            self.startedAt = startedAt
            self.showTimer = showTimer
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case startedAt
            case showTimer
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
            showTimer = try container.decodeIfPresent(Bool.self, forKey: .showTimer) ?? false
        }
    }

    /// The static title to display in the Live Activity.
    public var title: String

    public init(title: String) {
        self.title = title
    }
}
#endif
