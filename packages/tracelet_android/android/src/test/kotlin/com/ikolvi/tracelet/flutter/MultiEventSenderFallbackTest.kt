package com.ikolvi.tracelet.flutter

import io.flutter.plugin.common.BinaryMessenger
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * #371 — an event dispatched into a fan-out that cannot receive it must reach
 * the headless task, not vanish.
 *
 * The state this pins is the one a swipe-kill leaves behind when another
 * plugin's background engine keeps the process alive: #364 correctly holds that
 * foreign engine out of [MultiEventSender], and `onDetachedFromEngine` then
 * removes the primary's own dispatcher — so the composite is **empty**. Every
 * `send*` was `dispatchers.forEach { … }`, a silent no-op on an empty list, and
 * `headlessFallback` lived on [EventDispatcher], i.e. on the members that were
 * no longer there. Native tracking kept running; Dart got nothing, with not
 * even a log line to say so.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class MultiEventSenderFallbackTest {

    private fun location(uuid: String): Map<String, Any?> = mapOf(
        "uuid" to uuid,
        "coords" to mapOf("latitude" to 1.0, "longitude" to 2.0),
    )

    /** A dispatcher with a live Pigeon `eventApi`, i.e. an attached engine. */
    private fun attachedDispatcher(): EventDispatcher = EventDispatcher().apply {
        register(mock(BinaryMessenger::class.java))
    }

    @Test
    fun emptyFanOut_routesToTheHeadlessTask() {
        val routed = mutableListOf<Pair<String, Map<String, Any?>>>()
        val sender = MultiEventSender()
        sender.headlessFallback = { name, data -> routed.add(name to data) }

        // The post-task-removal state: primary detached, foreign engine alive
        // but (correctly, #364) never a member.
        sender.sendLocation(location("after-swipe"))

        assertEquals(1, routed.size, "an empty fan-out must fall back to the headless task")
        assertEquals("location", routed.single().first)
        assertEquals("after-swipe", routed.single().second["uuid"])
    }

    @Test
    fun everyEventKind_reachesTheHeadlessTaskFromAnEmptyFanOut() {
        val routed = mutableListOf<String>()
        val sender = MultiEventSender()
        sender.headlessFallback = { name, _ -> routed.add(name) }

        sender.sendLocation(location("l"))
        sender.sendMotionChange(location("m"))
        sender.sendGeofence(mapOf("geofence" to mapOf("identifier" to "home")))
        sender.sendHeartbeat(mapOf("location" to location("h")))
        sender.sendGeofencesChange(mapOf("on" to emptyList<Any?>()))
        sender.sendActivityChange(mapOf("activity" to "still"))
        sender.sendProviderChange(mapOf("enabled" to true))
        sender.sendEnabledChange(false)
        sender.sendPowerSaveChange(true)

        assertEquals(
            listOf(
                "location",
                "motionchange",
                "geofence",
                "heartbeat",
                "geofenceschange",
                "activitychange",
                "providerchange",
                "enabledchange",
                "powersavechange",
            ),
            routed,
            "no event kind may be left without a route when the fan-out is empty",
        )
    }

    /**
     * The guard against over-correcting: while a real engine is attached, the
     * event belongs to it and must NOT also be delivered to the headless task —
     * that would run the app's background callback for every foreground fix.
     */
    @Test
    fun liveFanOut_doesNotRouteToTheHeadlessTask() {
        var routed = 0
        val sender = MultiEventSender()
        sender.headlessFallback = { _, _ -> routed++ }
        sender.add(attachedDispatcher())

        sender.sendLocation(location("foreground"))

        assertEquals(0, routed, "an attached engine already received this event")
    }

    /**
     * A member whose engine went away (`unregister()`, so `eventApi == null`)
     * cannot receive either. It has its own fallback for that, but when the
     * composite carries one the routing decision is taken once, at the top —
     * otherwise N dead members would each dispatch the same event to the
     * headless task.
     */
    @Test
    fun membersThatCannotReceive_routeOnceNotPerMember() {
        var routed = 0
        val sender = MultiEventSender()
        sender.headlessFallback = { _, _ -> routed++ }
        repeat(3) { sender.add(EventDispatcher().apply { headlessFallback = { _, _ -> routed++ } }) }

        sender.sendLocation(location("dead-engines"))

        assertEquals(1, routed, "one event must produce one headless dispatch")
    }

    /**
     * Before any primary attach there is no HeadlessTaskService to route to, so
     * the members keep their previous behaviour rather than the event being
     * dropped on a null composite fallback.
     */
    @Test
    fun withoutACompositeFallback_membersStillFallBackThemselves() {
        val routed = mutableListOf<String>()
        val sender = MultiEventSender()
        sender.add(EventDispatcher().apply { headlessFallback = { name, _ -> routed.add(name) } })

        sender.sendLocation(location("no-composite-fallback"))

        assertEquals(listOf("location"), routed)
    }

    @Test
    fun removingTheLastMember_restoresHeadlessRouting() {
        var routed = 0
        val sender = MultiEventSender()
        sender.headlessFallback = { _, _ -> routed++ }
        val primary = attachedDispatcher()
        sender.add(primary)

        sender.sendLocation(location("before-detach"))
        assertEquals(0, routed)

        // Task removal: onDetachedFromEngine removes the primary's dispatcher.
        sender.remove(primary)
        sender.sendLocation(location("after-detach"))

        assertTrue(routed == 1, "the same sender must switch to headless once emptied")
    }
}
