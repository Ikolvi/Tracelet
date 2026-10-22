package com.ikolvi.tracelet.sdk

/**
 * Feeds every motion change the session emits to the native trip manager, and
 * stamps the result's trip id on the event (#442).
 *
 * The trip manager used to be fed only by `TraceletSdk.handleMotionStateChange`,
 * which SMART mode leaves early through the coordinator, and which SPEED-mode
 * transitions never reach. Those paths emit their own motion changes, so in
 * either mode no native trip ever started: no `trip_id` on rows (#402), no
 * trip summary (#401). Every one of them goes through the session's event
 * sender, so this is the one place all modes share.
 *
 * Re-sending the current state (a provider change, a re-dispatch) is not a
 * transition, and the trip manager ignores it.
 */
internal class TripStampingEventSender(
    val delegate: TraceletEventSender,
    private val onMotionChange: (Map<String, Any?>) -> Map<String, Any?>,
) : TraceletEventSender by delegate {
    override fun sendMotionChange(data: Map<String, Any?>) {
        delegate.sendMotionChange(onMotionChange(data))
    }
}
