package com.mesting.music

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

private fun varint(value: Long): ByteArray {
    var remaining = value
    val out = ByteArrayOutputStream()
    do {
        val next = remaining ushr 7
        out.write((remaining and 127).toInt() or if (next != 0L) 128 else 0)
        remaining = next
    } while (remaining != 0L)
    return out.toByteArray()
}
private fun number(field: Int, value: Long) = varint((field * 8).toLong()) + varint(value)
private fun blob(field: Int, value: ByteArray) = varint((field * 8 + 2).toLong()) + varint(value.size.toLong()) + value
private fun text(field: Int, value: String) = blob(field, value.toByteArray())
private fun frame(symbol: String = "qglinternal::vkCmdBeginRenderPass") =
    number(1, 0x1234) + text(4, symbol) +
        text(6, "/data/app/PRIVATE-PATH/lib/arm64/vulkan.adreno.so") + text(8, "0123abcdef")
private fun thread(frames: Int = 1, name: String = "1.raster"): ByteArray {
    var data = number(1, 7) + text(2, name) + text(5, "PRIVATE-MEMORY")
    repeat(frames) { data += blob(4, frame()) }
    return data
}
private fun tombstone(data: ByteArray = thread(), reverseOrder: Boolean = false): ByteArray {
    val entry = if (reverseOrder) blob(2, data) + number(1, 7) else number(1, 7) + blob(2, data)
    return text(9, "PRIVATE-ACCOUNT https://private.invalid/music") +
        blob(16, entry) + number(6, 7) +
        blob(10, number(1, 11) + text(2, "SIGSEGV") + number(3, 1) + text(4, "SEGV_MAPERR") + number(8, 1) + number(9, 0x1c)) +
        text(14, "PRIVATE-ABORT") + text(18, "PRIVATE-LOG") + text(1001, "PRIVATE-VENDOR")
}

fun main() {
    var passed = 0
    fun test(name: String, body: () -> Unit) {
        body(); passed++; println("PASS: $name")
    }
    test("known AOSP signal, thread and frame; all private payloads omitted") {
        val result = NativeCrashTrace.read(ByteArrayInputStream(tombstone()))
        check(result["status"] == "available")
        val report = result.toString()
        check("SIGSEGV" in report && "1.raster" in report && "vulkan.adreno.so" in report)
        check("vkCmdBeginRenderPass" in report && "0x1c" in report && "0123abcdef" in report)
        check("PRIVATE" !in report && "https:" !in report && "/data" !in report)
    }
    test("map value before key and crashing tid after thread map") {
        check(NativeCrashTrace.read(ByteArrayInputStream(tombstone(reverseOrder = true)))["status"] == "available")
    }
    test("only the crashing thread is exported") {
        val other = blob(16, number(1, 8) + blob(2, text(2, "PRIVATE-THREAD") + blob(4, frame("PrivateNonCrashingFunction"))))
        val result = NativeCrashTrace.read(ByteArrayInputStream(other + tombstone())).toString()
        check("PrivateNonCrashingFunction" !in result && "PRIVATE" !in result)
    }
    test("frame count is capped; later fields are still read") {
        val result = NativeCrashTrace.read(ByteArrayInputStream(tombstone(thread(90))))
        val frames = (result["thread"] as Map<*, *>)["frames"] as List<*>
        check(frames.size == 24 && (result["signal"] as Map<*, *>)["name"] == "SIGSEGV")
    }
    test("unknown thread names and URL-like function names are removed") {
        val data = text(2, "private@example.invalid") + blob(4, frame("https://private.invalid/token"))
        val result = NativeCrashTrace.read(ByteArrayInputStream(tombstone(data))).toString()
        check("name=other" in result && "private" !in result && "token" !in result)
    }
    test("protobuf default zero fault address is retained when present flag is true") {
        val signal = blob(10, number(1, 11) + number(8, 1))
        val base = number(6, 7) + blob(16, number(1, 7) + blob(2, thread()))
        val result = NativeCrashTrace.read(ByteArrayInputStream(base + signal)).toString()
        check("faultAddress=0x0" in result)
    }
    test("negative int32 signal code uses the ten-byte varint representation") {
        val result = NativeCrashTrace.read(ByteArrayInputStream(tombstone() + blob(10, number(3, -6))))
        check((result["signal"] as Map<*, *>)["code"] == -6)
    }
    test("empty or missing crashing thread is explicit") {
        check(NativeCrashTrace.read(ByteArrayInputStream(byteArrayOf()))["status"] == "thread_unavailable")
        check(NativeCrashTrace.read(ByteArrayInputStream(number(6, 999)))["status"] == "thread_unavailable")
    }
    test("truncation and invalid field/wire/varint cannot escape as exceptions") {
        val good = tombstone()
        for (length in 1 until good.size step 7) {
            val result = NativeCrashTrace.read(ByteArrayInputStream(good.copyOf(length)))
            check(result["status"] in setOf("available", "thread_unavailable", "invalid_or_unavailable"))
        }
        for (bad in listOf(byteArrayOf(0), byteArrayOf(11), ByteArray(12) { 255.toByte() }, blob(16, byteArrayOf(18, 100, 1)))) {
            check(NativeCrashTrace.read(ByteArrayInputStream(bad))["status"] != "available")
        }
    }
    test("large opaque memory is skipped without exporting or decoding it") {
        val memory = blob(17, ByteArray(3 * 1024 * 1024) { 91 })
        check(NativeCrashTrace.read(ByteArrayInputStream(memory + tombstone()))["status"] == "available")
    }
    test("oversized field stops within the bounded scan") {
        val prefix = varint(17 * 8 + 2L) + varint(20 * 1024 * 1024L)
        var bytesRead = 0
        val infinite = object : InputStream() {
            override fun read(): Int = if (bytesRead < prefix.size) prefix[bytesRead++].toInt() and 255 else { bytesRead++; 0 }
        }
        check(NativeCrashTrace.read(infinite)["status"] != "available")
        check(bytesRead <= 8192)
    }
    println("NATIVE_TRACE_TESTS_PASSED=$passed")
}
