package com.mesting.music

/** Pure scheduling state owned by Together's worker thread. Android delivery,
 * power management and the platform channel are deliberately outside this
 * class, so missing/late acknowledgements can be tested with a monotonic clock.
 * No room/account identity is carried: lease is an opaque ownership generation. */
internal class TogetherPulseScheduler(
    private val intervalMs: Long = 5_000,
    private val acknowledgementMs: Long = 12_000,
    private val leaseMs: Long = 120_000,
) {
    data class Request(val lease: String, val id: Long) {
        @Volatile var deliverable: Boolean = true
    }
    private var revision = -1L
    private var lease: String? = null
    private var enabled = false
    private var nextId = 0L
    private var nextPulse = 0L
    private var pending: Request? = null
    private var deadline = 0L
    private var expires = 0L
    val isEnabled: Boolean get() = enabled
    var sent = 0L; private set
    var acknowledged = 0L; private set
    var timedOut = 0L; private set
    var rejected = 0L; private set

    fun configure(nextRevision: Long, nextLease: String?, active: Boolean, now: Long): Boolean {
        if (nextRevision < revision) return false
        if (nextRevision == revision) {
            // Configuration retries after a lost reply are idempotent.
            return nextLease == lease && active == enabled
        }
        pending?.deliverable = false
        revision = nextRevision
        lease = nextLease
        enabled = active && !nextLease.isNullOrEmpty()
        pending = null
        nextPulse = now
        expires = now + leaseMs
        return true
    }

    fun poll(now: Long): Request? {
        if (!enabled) return null
        if (now >= expires) { stop(); return null }
        if (pending != null && now >= deadline) {
            timedOut++
            pending?.deliverable = false
            pending = null
        }
        if (pending != null || now < nextPulse) return null
        val request = Request(lease ?: return null, ++nextId)
        pending = request
        deadline = now + acknowledgementMs
        nextPulse = now + intervalMs
        sent++
        return request
    }

    fun current(request: Request): Boolean = enabled && pending == request

    fun finish(request: Request, accepted: Boolean, now: Long) {
        // A timeout/configuration may already have issued another request.
        // Its in-flight protection must survive an old platform callback.
        if (!current(request)) return
        if (accepted) acknowledged++ else rejected++
        if (accepted) expires = now + leaseMs
        request.deliverable = false
        pending = null
    }

    fun stop() {
        enabled = false
        pending?.deliverable = false
        pending = null
        lease = null
    }

    fun diagnostics(): Map<String, Long> = mapOf(
        "nativePulses" to sent,
        "nativeAcknowledged" to acknowledged,
        "nativeTimeouts" to timedOut,
        "nativeRejected" to rejected,
    )
}
