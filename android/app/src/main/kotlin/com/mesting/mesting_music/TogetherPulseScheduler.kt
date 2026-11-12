package com.mesting.music

import java.util.ArrayDeque

/** Pure scheduling state owned by Together's worker thread. Android delivery,
 * power management and the platform channel are deliberately outside this
 * class, so missing/late acknowledgements can be tested with a monotonic clock.
 * No room/account identity is carried: lease is an opaque ownership generation. */
internal class TogetherPulseScheduler(
    private val intervalMs: Long = 5_000,
    private val acknowledgementMs: Long = 12_000,
    private val leaseMs: Long = 120_000,
    private val timelineCapacity: Int = 256,
    private val wallClock: () -> Long = System::currentTimeMillis,
    private val eventSink: ((Map<String, Any>) -> Unit)? = null,
) {
    /** Fixed export vocabulary. No lease, room, user, song, URL, error text or
     * arbitrary channel payload can be attached to a diagnostic event. */
    enum class Phase {
        engineAttached, configuration, configurationRejected,
        pulseScheduled, pulseSent, pulseUndeliverable, acknowledged, rejected,
        staleAcknowledgement, acknowledgementTimeout, leaseExpired,
        mediaServicePresent, mediaServiceMissing, wakeAcquired, wakeReleased, stopped,
        foregroundLeaseAcquired, foregroundLeaseRejected,
    }
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
    private val timeline = ArrayDeque<Map<String, Any>>()
    private var eventIndex = 0L
    private var droppedEvents = 0L

    init { require(timelineCapacity > 0) }

    fun record(phase: Phase, now: Long, requestId: Long? = null, accepted: Boolean? = null) {
        if (timeline.size == timelineCapacity) {
            timeline.removeFirst()
            droppedEvents++
        }
        val event = buildMap<String, Any> {
            put("index", ++eventIndex)
            put("utcMs", wallClock())
            put("elapsedMs", now)
            put("phase", phase.name)
            put("revision", revision)
            put("enabled", enabled)
            if (requestId != null) put("request", requestId)
            if (accepted != null) put("accepted", accepted)
        }
        timeline.addLast(event)
        // Observers receive the same whitelist and a detached map. A broken
        // diagnostic sink must not stop the native schedule or room lease.
        runCatching { eventSink?.invoke(event.toMap()) }
    }

    fun configure(nextRevision: Long, nextLease: String?, active: Boolean, now: Long): Boolean {
        if (nextRevision < revision) {
            record(Phase.configurationRejected, now, accepted = false)
            return false
        }
        if (nextRevision == revision) {
            // Configuration retries after a lost reply are idempotent.
            val accepted = nextLease == lease && active == enabled
            record(if (accepted) Phase.configuration else Phase.configurationRejected, now, accepted = accepted)
            return accepted
        }
        pending?.deliverable = false
        revision = nextRevision
        lease = nextLease
        enabled = active && !nextLease.isNullOrEmpty()
        pending = null
        nextPulse = now
        expires = now + leaseMs
        record(Phase.configuration, now, accepted = true)
        return true
    }

    fun poll(now: Long): Request? {
        if (!enabled) return null
        if (now >= expires) {
            record(Phase.leaseExpired, now)
            stop(now)
            return null
        }
        if (pending != null && now >= deadline) {
            timedOut++
            record(Phase.acknowledgementTimeout, now, pending?.id)
            pending?.deliverable = false
            pending = null
        }
        if (pending != null || now < nextPulse) return null
        val request = Request(lease ?: return null, ++nextId)
        pending = request
        deadline = now + acknowledgementMs
        nextPulse = now + intervalMs
        sent++
        record(Phase.pulseScheduled, now, request.id)
        return request
    }

    fun current(request: Request): Boolean = enabled && pending == request

    fun finish(request: Request, accepted: Boolean, now: Long) {
        // A timeout/configuration may already have issued another request.
        // Its in-flight protection must survive an old platform callback.
        if (!current(request)) {
            record(Phase.staleAcknowledgement, now, request.id, accepted)
            return
        }
        if (accepted) acknowledged++ else rejected++
        record(if (accepted) Phase.acknowledged else Phase.rejected, now, request.id, accepted)
        if (accepted) expires = now + leaseMs
        request.deliverable = false
        pending = null
    }

    fun stop(now: Long? = null) {
        enabled = false
        pending?.deliverable = false
        pending = null
        lease = null
        if (now != null) record(Phase.stopped, now)
    }

    fun diagnostics(): Map<String, Long> = mapOf(
        "nativePulses" to sent,
        "nativeAcknowledged" to acknowledged,
        "nativeTimeouts" to timedOut,
        "nativeRejected" to rejected,
    )

    /** A detached snapshot prevents export from mutating the worker journal. */
    fun diagnosticSnapshot(): Map<String, Any> = mapOf(
        "capacity" to timelineCapacity,
        "dropped" to droppedEvents,
        "enabled" to enabled,
        "pending" to (pending != null),
        "counts" to diagnostics(),
        "events" to timeline.map { it.toMap() },
    )
}
