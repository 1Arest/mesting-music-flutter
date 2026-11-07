package com.mesting.music

import java.io.BufferedInputStream
import java.io.InputStream

/** Narrow reader for AOSP debuggerd/proto/tombstone.proto (Android 16 schema).
 * Reads only the crashing thread, signal and bounded native frames. Command
 * lines, abort strings, logs, registers, memory and open-file data are skipped;
 * they must never enter the copyable diagnostic report. No protobuf dependency
 * or permission is added. Unknown vendor fields use standard wire-type skips.
 * Schema: https://android.googlesource.com/platform/system/core/+/android16-release/debuggerd/proto/tombstone.proto
 */
object NativeCrashTrace {
    private const val MAX_BYTES = 4 * 1024 * 1024
    private const val MAX_THREADS = 128
    private const val MAX_FRAMES = 24
    private val libraries = Regex("[A-Za-z0-9_.-]{1,128}\\.so(?:\\.[0-9]+)*")
    private val symbols = Regex("[A-Za-z_~][A-Za-z0-9_\\$:<>() ,.*+~&\\[\\]=!-]{0,159}")
    private val hex = Regex("[a-fA-F0-9]{1,128}")
    private val signalNames = setOf("SIGSEGV", "SIGABRT", "SIGBUS", "SIGILL", "SIGFPE", "SIGTRAP", "SIGSYS", "SIGPIPE")

    fun read(input: InputStream): Map<String, Any> = try {
        val cursor = Cursor(BufferedInputStream(input), System.nanoTime() + 1_000_000_000L)
        val root = Reader(cursor, MAX_BYTES.toLong(), root = true)
        var tid = 0L
        var hasFaultAddress = false
        var faultAddress = 0L
        val signal = mutableMapOf<String, Any>()
        val threads = mutableMapOf<Long, Map<String, Any>>()
        root.fields { field, wire ->
            when {
                field == 6 && wire == 0 -> tid = root.number()
                field == 10 && wire == 2 -> root.message { child ->
                    child.fields { key, kind ->
                        when {
                            key == 1 && kind == 0 -> signal["number"] = child.number().toInt()
                            key == 2 && kind == 2 -> child.text(32).let { if (it in signalNames) signal["name"] = it }
                            key == 3 && kind == 0 -> signal["code"] = child.number().toInt()
                            key == 4 && kind == 2 -> child.text(48).let { if (Regex("[A-Z0-9_]{1,48}").matches(it)) signal["codeName"] = it }
                            key == 8 && kind == 0 -> hasFaultAddress = child.number() != 0L
                            key == 9 && kind == 0 -> faultAddress = child.number()
                            else -> child.skip(kind)
                        }
                    }
                }
                field == 16 && wire == 2 -> root.message { entry ->
                    var key = 0L
                    var selectedThread: Map<String, Any>? = null
                    entry.fields { number, kind ->
                        when {
                            number == 1 && kind == 0 -> key = entry.number()
                            number == 2 && kind == 2 && threads.size < MAX_THREADS -> entry.message { selectedThread = readThread(it) }
                            else -> entry.skip(kind)
                        }
                    }
                    // Map entries can put the value before the key. Keep a
                    // bounded candidate set until the top-level tid is known.
                    if (threads.size < MAX_THREADS) selectedThread?.let { threads[key] = it }
                }
                else -> root.skip(wire)
            }
        }
        if (hasFaultAddress) signal["faultAddress"] = "0x" + java.lang.Long.toUnsignedString(faultAddress, 16)
        val crashed = threads[tid]
        if (crashed == null || tid <= 0) mapOf("status" to "thread_unavailable")
        else mapOf("status" to "available", "signal" to signal, "thread" to crashed)
    } catch (_: LimitExceeded) {
        mapOf("status" to "limit_exceeded")
    } catch (_: Exception) {
        // Never copy an exception message: it can include paths or file data.
        mapOf("status" to "invalid_or_unavailable")
    }

    private fun readThread(reader: Reader): Map<String, Any> {
        var name = "other"
        val frames = mutableListOf<Map<String, Any>>()
        reader.fields { field, wire ->
            when {
                field == 2 && wire == 2 -> {
                    val value = reader.text(64)
                    if (value == "main" || Regex("(?:io\\.flutter\\.)?[0-9]+\\.(?:raster|ui|io|platform)").matches(value)) name = value
                }
                field == 4 && wire == 2 && frames.size < MAX_FRAMES -> reader.message { frames.add(readFrame(it)) }
                else -> reader.skip(wire)
            }
        }
        return mapOf("name" to name, "frames" to frames)
    }

    private fun readFrame(reader: Reader): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        reader.fields { field, wire ->
            when {
                field == 1 && wire == 0 -> result["relativePc"] = "0x" + java.lang.Long.toUnsignedString(reader.number(), 16)
                field == 4 && wire == 2 -> reader.text(160).let { if (symbols.matches(it)) result["function"] = it }
                field == 6 && wire == 2 -> {
                    val value = reader.text(1024).substringAfterLast('/').substringAfterLast('\\')
                    if (libraries.matches(value)) result["library"] = value
                }
                field == 8 && wire == 2 -> reader.text(128).let { if (hex.matches(it)) result["buildId"] = it.lowercase() }
                else -> reader.skip(wire)
            }
        }
        return result
    }

    private class LimitExceeded : Exception()
    private class Cursor(val input: InputStream, val deadline: Long) {
        var position = 0L
        fun check(amount: Long) {
            if (amount < 0 || amount > MAX_BYTES - position || System.nanoTime() > deadline) throw LimitExceeded()
        }
        fun byte(): Int {
            check(1)
            val value = input.read()
            if (value >= 0) position++
            return value
        }
        fun skip(amount: Long) {
            check(amount)
            var remaining = amount
            while (remaining > 0) {
                check(remaining)
                val read = input.skip(remaining)
                if (read > 0) { position += read; remaining -= read }
                else { if (byte() < 0) throw IllegalArgumentException(); remaining-- }
            }
        }
    }

    /** Children share one cursor and cannot cross their length-delimited end.
     * Only bounded allowlisted strings allocate bytes; opaque messages skip.
     */
    private class Reader(val cursor: Cursor, val end: Long, val root: Boolean = false) {
        fun fields(action: (Int, Int) -> Unit) {
            while (cursor.position < end) {
                val first = cursor.byte()
                if (first < 0) { if (root) return else throw IllegalArgumentException() }
                val tag = number(first)
                if (tag < 8 || tag > 0xffff_ffffL) throw IllegalArgumentException()
                action((tag ushr 3).toInt(), (tag and 7).toInt())
            }
            if (cursor.position != end) throw IllegalArgumentException()
            // The root end is a safety ceiling, not a declared message length.
            // Never label a prefix cut at that ceiling as a complete trace.
            if (root) throw LimitExceeded()
        }
        fun number(first: Int = next()): Long {
            var byte = first
            var value = 0L
            for (shift in 0..63 step 7) {
                if (shift == 63 && byte > 1) throw IllegalArgumentException()
                value = value or ((byte and 127).toLong() shl shift)
                if (byte and 128 == 0) return value
                byte = next()
            }
            throw IllegalArgumentException()
        }
        private fun next(): Int {
            if (cursor.position >= end) throw IllegalArgumentException()
            return cursor.byte().also { if (it < 0) throw IllegalArgumentException() }
        }
        private fun length(): Long {
            val size = number()
            if (size < 0 || size > end - cursor.position) throw IllegalArgumentException()
            cursor.check(size)
            return size
        }
        fun message(block: (Reader) -> Unit) {
            val size = length()
            val childEnd = cursor.position + size
            val child = Reader(cursor, childEnd)
            block(child)
            if (cursor.position != child.end) throw IllegalArgumentException()
        }
        fun text(maxBytes: Int): String {
            val size = length()
            if (size > maxBytes) { cursor.skip(size); return "" }
            val bytes = ByteArray(size.toInt())
            for (i in bytes.indices) bytes[i] = next().toByte()
            return bytes.toString(Charsets.UTF_8)
        }
        fun skip(wire: Int) {
            when (wire) {
                0 -> number()
                1 -> skipFixed(8)
                2 -> cursor.skip(length())
                5 -> skipFixed(4)
                else -> throw IllegalArgumentException()
            }
        }
        private fun skipFixed(count: Long) {
            if (count > end - cursor.position) throw IllegalArgumentException()
            cursor.skip(count)
        }
    }
}
