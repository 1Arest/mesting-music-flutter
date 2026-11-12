package com.mesting.music

import java.util.Collections
import java.util.IdentityHashMap

/** Main-thread ownership for the existing media service's Together lease.
 * The Android port alone knows notifications/services; this state machine
 * handles overlapping engine owners and never models real playback as fake
 * "playing". It can therefore be verified without Android or an account. */
class TogetherMediaLeaseCoordinator(private val port: Port) {
    interface Port {
        fun isForeground(): Boolean
        fun promote(): Boolean
        fun releaseIfOwned(): Boolean
    }

    enum class Outcome { alreadyForeground, acquired, rejected }

    private val owners = Collections.newSetFromMap(IdentityHashMap<Any, Boolean>())

    fun acquire(owner: Any): Outcome {
        owners.add(owner)
        return if (port.isForeground()) Outcome.alreadyForeground
        else if (port.promote()) Outcome.acquired
        else Outcome.rejected
    }

    fun release(owner: Any): Boolean {
        if (!owners.remove(owner) || owners.isNotEmpty()) return false
        return port.releaseIfOwned()
    }
}
