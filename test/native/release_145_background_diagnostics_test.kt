package com.mesting.music

/** Host-only production scheduler checks: an ACK is delivery evidence, and
 * cannot assert anything about Dart HTTP or player completion. */
fun main() {
    var passed = 0
    fun scenario(name: String, run: () -> Unit) {
        run(); passed++; println("PASS $name")
    }
    scenario("scheduled, sent, timeout and stale acknowledgement are distinct") {
        val state = TogetherPulseScheduler(wallClock = { 1234 })
        state.configure(1, "PRIVATE_ROOM_LEASE", true, 0)
        val first = state.poll(0)!!
        state.record(TogetherPulseScheduler.Phase.pulseSent, 1, first.id)
        val newer = state.poll(12_000)!!
        state.finish(first, true, 12_001)
        check(state.current(newer))
        val text = state.diagnosticSnapshot().toString()
        check(text.contains("pulseScheduled") && text.contains("pulseSent"))
        check(text.contains("acknowledgementTimeout") && text.contains("staleAcknowledgement"))
        check(!text.contains("PRIVATE_") && !text.contains("lease="))
        check(text.contains("utcMs=1234"))
    }
    scenario("acknowledgement keeps its delivery-only counter and pending state") {
        val state = TogetherPulseScheduler()
        state.configure(1, "PRIVATE_LEASE", true, 0)
        state.finish(state.poll(0)!!, true, 1)
        val snapshot = state.diagnosticSnapshot()
        check(snapshot["enabled"] == true && snapshot["pending"] == false)
        check(state.diagnostics()["nativeAcknowledged"] == 1L)
        check(!snapshot.toString().contains("httpCompleted"))
    }
    scenario("bounded native history retains the newest detached events") {
        val state = TogetherPulseScheduler(timelineCapacity = 5)
        state.configure(1, "PRIVATE_LEASE", true, 0)
        for (i in 0L..10L) {
            val request = state.poll(i * 5_000)!!
            state.finish(request, true, i * 5_000 + 1)
        }
        val snapshot = state.diagnosticSnapshot()
        val events = snapshot["events"] as List<*>
        check(events.size == 5 && (snapshot["dropped"] as Long) > 0)
        val last = events.last() as Map<*, *>
        check(last["phase"] == "acknowledged" && last["request"] == 11L)
        check(!snapshot.toString().contains("PRIVATE_"))
    }
    scenario("optional log observer receives only detached safe events") {
        val observed = mutableListOf<Map<String, Any>>()
        val state = TogetherPulseScheduler(eventSink = { observed.add(it) })
        state.configure(1, "PRIVATE_LEASE", true, 0)
        state.finish(state.poll(0)!!, true, 1)
        check(observed.last()["phase"] == "acknowledged")
        check(!observed.toString().contains("PRIVATE_"))
        val broken = TogetherPulseScheduler(eventSink = { error("PRIVATE_SINK_ERROR") })
        check(broken.configure(1, "PRIVATE_LEASE", true, 0))
        check(broken.poll(0) != null && broken.sent == 1L)
    }
    println("$passed native diagnostics scenarios passed")
}
