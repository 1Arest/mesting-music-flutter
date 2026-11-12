package com.mesting.music

/** Exercise the production ownership state machine with a deterministic media
 * service boundary. Android foreground/service behavior is verified on-device. */
fun main() {
    class Media : TogetherMediaLeaseCoordinator.Port {
        var foreground = false
        var leaseNotification = false
        var allowPromotion = true
        var promotions = 0
        var withdrawals = 0
        override fun isForeground() = foreground
        override fun promote(): Boolean {
            if (!allowPromotion) return false
            promotions++
            foreground = true
            leaseNotification = true
            return true
        }
        override fun releaseIfOwned(): Boolean {
            if (!leaseNotification) return false
            withdrawals++
            foreground = false
            leaseNotification = false
            return true
        }
    }
    var passed = 0
    fun scenario(name: String, run: () -> Unit) {
        run(); passed++; println("PASS $name")
    }
    scenario("cold paused room acquires the existing media foreground owner") {
        val media = Media()
        val state = TogetherMediaLeaseCoordinator(media)
        val owner = Any()
        check(state.acquire(owner) == TogetherMediaLeaseCoordinator.Outcome.acquired)
        check(media.foreground && media.promotions == 1)
        check(state.release(owner) && media.withdrawals == 1)
    }
    scenario("ordinary playback is observed and never withdrawn") {
        val media = Media().apply { foreground = true }
        val state = TogetherMediaLeaseCoordinator(media)
        val owner = Any()
        check(state.acquire(owner) == TogetherMediaLeaseCoordinator.Outcome.alreadyForeground)
        check(!state.release(owner) && media.foreground && media.promotions == 0)
    }
    scenario("old engine teardown preserves a newer engine lease") {
        val media = Media()
        val state = TogetherMediaLeaseCoordinator(media)
        val old = Any(); val current = Any()
        state.acquire(old); state.acquire(current)
        check(!state.release(old) && media.foreground)
        check(!state.release(old) && media.withdrawals == 0)
        check(state.release(current) && media.withdrawals == 1)
    }
    scenario("duplicate requests are idempotent and equal owners stay distinct") {
        data class Owner(val equal: Int)
        val media = Media()
        val state = TogetherMediaLeaseCoordinator(media)
        val first = Owner(1); val second = Owner(1)
        state.acquire(first); state.acquire(first); state.acquire(second)
        check(media.promotions == 1)
        check(!state.release(first))
        check(state.release(second) && media.withdrawals == 1)
    }
    scenario("rejected promotion retries and real playback takes over the notification") {
        val media = Media().apply { allowPromotion = false }
        val state = TogetherMediaLeaseCoordinator(media)
        val owner = Any()
        check(state.acquire(owner) == TogetherMediaLeaseCoordinator.Outcome.rejected)
        media.allowPromotion = true
        check(state.acquire(owner) == TogetherMediaLeaseCoordinator.Outcome.acquired)
        // AudioService replaces the same notification with its actual media
        // controls. The Together-specific marker no longer belongs to us.
        media.leaseNotification = false
        check(!state.release(owner) && media.foreground && media.withdrawals == 0)
    }
    scenario("an unresponsive engine expires its scheduling and media owners") {
        val media = Media()
        val state = TogetherMediaLeaseCoordinator(media)
        val scheduler = TogetherPulseScheduler(leaseMs = 20_000)
        val owner = Any()
        scheduler.configure(1, "opaque", true, 0)
        val request = scheduler.poll(0)!!
        state.acquire(owner)
        check(scheduler.poll(20_000) == null && !scheduler.isEnabled)
        check(state.release(owner) && media.withdrawals == 1)
        scheduler.finish(request, true, 20_001)
        check(!scheduler.isEnabled && !state.release(owner))
    }
    println("$passed native media_lease scenarios passed")
}
