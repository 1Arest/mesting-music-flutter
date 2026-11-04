package com.mesting.music

/** Standalone JVM assertions execute the production scheduling state machine;
 * there is no Android mock, sleeping, device, account or network dependency. */
fun main() {
    var passed = 0
    fun scenario(name: String, run: () -> Unit) {
        run(); passed++; println("PASS $name")
    }
    scenario("five-second cadence survives a missing acknowledgement") {
        val state = TogetherPulseScheduler()
        check(state.configure(1, "opaque-a", true, 0))
        val first = state.poll(0)!!
        check(state.poll(5_000) == null)
        val recovered = state.poll(12_000)!!
        check(recovered.id > first.id && !first.deliverable)
        state.finish(first, true, 12_001)
        check(state.current(recovered))
        state.finish(recovered, true, 12_002)
        check(state.poll(16_999) == null)
        check(state.poll(17_000) != null)
        check(state.timedOut == 1L && state.acknowledged == 1L)
    }
    scenario("new lease rejects an old revision and late callbacks") {
        val state = TogetherPulseScheduler()
        state.configure(2, "opaque-a", true, 0)
        val old = state.poll(0)!!
        check(state.configure(3, "opaque-b", true, 1))
        val current = state.poll(1)!!
        check(!state.configure(2, "opaque-a", false, 2))
        state.finish(old, true, 2)
        check(state.current(current) && !old.deliverable)
    }
    scenario("configuration replay is idempotent") {
        val state = TogetherPulseScheduler()
        state.configure(1, "opaque", true, 0)
        val request = state.poll(0)!!
        check(state.configure(1, "opaque", true, 1))
        check(state.current(request) && state.poll(1) == null)
        check(!state.configure(1, "different", true, 2))
    }
    scenario("exit releases pending delivery and disables ordinary pulses") {
        val state = TogetherPulseScheduler()
        state.configure(1, "opaque", true, 0)
        val old = state.poll(0)!!
        state.configure(2, "stop", false, 1)
        check(!old.deliverable && state.poll(100_000) == null)
        check(!state.isEnabled)
    }
    scenario("unresponsive engine loses lease and fallback may renew it") {
        val state = TogetherPulseScheduler(leaseMs = 20_000)
        state.configure(1, "opaque", true, 0)
        state.poll(0)
        check(state.poll(20_000) == null && !state.isEnabled)
        check(state.configure(2, "renewed", true, 20_001))
        check(state.poll(20_001)?.lease == "renewed")
    }
    scenario("acknowledgements renew the bounded lease without room identifiers") {
        val state = TogetherPulseScheduler(leaseMs = 20_000)
        state.configure(1, "opaque", true, 0)
        state.finish(state.poll(0)!!, true, 10_000)
        check(state.poll(25_000) != null)
        check(state.diagnostics().keys == setOf("nativePulses", "nativeAcknowledged", "nativeTimeouts", "nativeRejected"))
    }
    println("$passed native scheduler scenarios passed")
}
