package com.mesting.music

/** A narrow opt-in to driver recovery, not a device-model blacklist. An ANR,
 * memory pressure, Java error or unrelated native stack must not change GPU.
 * Pure Kotlin so the exact predicate is covered without a phone or Android.
 */
object VulkanCrashSignature {
    fun matches(exit: Map<*, *>): Boolean {
        if (exit["reason"] != "native_crash" || exit["status"] != 11) return false
        val trace = exit["nativeTrace"] as? Map<*, *> ?: return false
        if (trace["status"] != "available") return false
        val signal = trace["signal"] as? Map<*, *> ?: return false
        if (signal["number"] != 11 || signal["code"] != 1) return false
        val thread = trace["thread"] as? Map<*, *> ?: return false
        if (!Regex("(?:io\\.flutter\\.)?[0-9]+\\.raster").matches(thread["name"] as? String ?: "")) return false
        val frames = thread["frames"] as? List<*> ?: return false
        val first = frames.firstOrNull() as? Map<*, *>
        // The allocation-failure reproduction has obfuscated driver frames,
        // but exactly the same build, fault address and top PC as the supplied
        // vkBeginCommandBuffer crash. Match that evidence without guessing a
        // function name or broadening recovery to unrelated native failures.
        if (signal["faultAddress"] == "0x1c" && first?.get("library") == "vulkan.adreno.so" &&
            first["buildId"] == "33f69a5b3c5ea87c251952c3e0b7a7a2" && first["relativePc"] == "0xd524c") return true
        return frames.take(4).any { value ->
            val f = value as? Map<*, *> ?: return@any false
            f["library"] == "vulkan.adreno.so" &&
                (f["function"] as? String).orEmpty().let {
                    it.contains("vkBeginCommandBuffer") || it.contains("vkCmdBeginRenderPass") || it.contains("vkCmdDraw")
                }
        }
    }
}
