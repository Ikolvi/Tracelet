import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// A default SwiftUI View that developers can use inside their Live Activity Widget.
#if canImport(ActivityKit) && canImport(WidgetKit)
@available(iOS 16.1, *)
public struct TraceletLiveActivityView: View {
    public let context: ActivityViewContext<TraceletActivityAttributes>
    
    public init(context: ActivityViewContext<TraceletActivityAttributes>) {
        self.context = context
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                Text(context.attributes.title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text(context.state.status)
                .font(.subheadline)
                .foregroundColor(.gray)
            if context.state.showTimer, let startedAt = context.state.startedAt {
                Text(timerInterval: min(startedAt, Date())...Date.distantFuture, countsDown: false)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.8))
        .activitySystemActionForegroundColor(Color.white)
    }
}
#endif
