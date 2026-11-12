package com.mesting.music

fun main() {
    fun exit(thread: String = "1.raster", library: String = "vulkan.adreno.so", signal: Int = 11,
             function: String = "qglinternal::vkBeginCommandBuffer(VkCommandBuffer_T*, VkCommandBufferBeginInfo const*)") =
        mapOf<String, Any>("reason" to "native_crash", "status" to 11,
            "nativeTrace" to mapOf("status" to "available", "signal" to mapOf("number" to signal, "code" to 1),
                "thread" to mapOf("name" to thread, "frames" to listOf(mapOf("library" to library, "function" to function)))))
    check(VulkanCrashSignature.matches(exit()))
    check(VulkanCrashSignature.matches(exit(function = "qglinternal::vkCmdBeginRenderPass")))
    check(!VulkanCrashSignature.matches(exit(thread = "main")))
    check(!VulkanCrashSignature.matches(exit(library = "libflutter.so")))
    check(!VulkanCrashSignature.matches(exit(signal = 6)))
    check(!VulkanCrashSignature.matches(exit(function = "unrelated")))
    check(!VulkanCrashSignature.matches(exit() + ("reason" to "low_memory")))
    check(!VulkanCrashSignature.matches(mapOf("reason" to "native_crash", "status" to 11)))
    val allocation = mapOf<String, Any>("reason" to "native_crash", "status" to 11,
        "nativeTrace" to mapOf("status" to "available", "signal" to mapOf("number" to 11, "code" to 1, "faultAddress" to "0x1c"),
            "thread" to mapOf("name" to "1.raster", "frames" to listOf(mapOf("library" to "vulkan.adreno.so",
                "buildId" to "33f69a5b3c5ea87c251952c3e0b7a7a2", "relativePc" to "0xd524c")))))
    check(VulkanCrashSignature.matches(allocation))
    val wrongTrace = (allocation["nativeTrace"] as Map<*, *>) + ("signal" to mapOf("number" to 11, "code" to 1, "faultAddress" to "0x8"))
    check(!VulkanCrashSignature.matches(allocation + ("nativeTrace" to wrongTrace)))
    println("Vulkan crash recovery signature: 10 passed")
}
